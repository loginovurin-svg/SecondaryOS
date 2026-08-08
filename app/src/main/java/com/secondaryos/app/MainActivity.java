package com.secondaryos.app;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.system.Os;
import android.util.Log;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    private static final String TAG = "SecondaryOS";
    private static final int INSTALL_VERSION = 1;

    private TextView logView;
    private Button startButton;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        startButton = new Button(this);
        startButton.setText("ЗАПУСТИТЬ LINUX (ЭТАП 0)");
        root.addView(startButton);

        ScrollView scroll = new ScrollView(this);
        logView = new TextView(this);
        logView.setTypeface(Typeface.MONOSPACE);
        logView.setTextSize(11f);
        logView.setText("Логи будут здесь...\n");
        scroll.addView(logView);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT));

        setContentView(root);

        startButton.setOnClickListener(v -> startLinux());
    }

    private void log(String msg) {
        Log.i(TAG, msg);
        mainHandler.post(() -> logView.append(msg + "\n"));
    }

    private void startLinux() {
        startButton.setEnabled(false);
        executor.execute(() -> {
            try {
                runDiagnostics();
            } catch (Throwable t) {
                log("✗ КРИТИЧЕСКАЯ ОШИБКА: " + t);
                Log.e(TAG, "fatal", t);
            } finally {
                mainHandler.post(() -> startButton.setEnabled(true));
            }
        });
    }

    private void runDiagnostics() throws Exception {
        log("=== Начало диагностики ===");

        File proot = prepareProot();
        log("proot: " + proot.getAbsolutePath() +
                " exists=" + proot.exists() +
                " exec=" + proot.canExecute());

        File rootfs = new File(getFilesDir(), "debian");
        File marker = new File(getFilesDir(), ".secondaryos_installed");
        String markerText = marker.exists() ? readFile(marker) : "";

        if (!markerText.equals(String.valueOf(INSTALL_VERSION)) || !rootfs.exists()) {
            log("Распаковываю rootfs...");
            if (rootfs.exists()) deleteRecursively(rootfs);
            extractRootfs(rootfs);
            writeFile(marker, String.valueOf(INSTALL_VERSION));
            log("Rootfs распакован.");
        } else {
            log("Rootfs уже распакован.");
        }

        // Writable-каталог для proot и для гостевого /tmp
        File tmpDir = new File(getFilesDir(), "tmp");
        tmpDir.mkdirs();
        log("PROOT_TMP_DIR: " + tmpDir.getAbsolutePath());

        // Проверка ключевых файлов с хост-стороны
        checkFile(rootfs, "bin");
        checkFile(rootfs, "lib");
        checkFile(rootfs, "usr/bin/bash");
        checkFile(rootfs, "usr/bin/dash");
        checkFile(rootfs, "lib/ld-linux-aarch64.so.1");
        checkFile(rootfs, "usr/lib/ld-linux-aarch64.so.1");

        // Тест A: прямой запуск ELF без оболочки
        List<String> a = new ArrayList<>();
        a.add("/usr/bin/uname"); a.add("-a");
        testLaunch(proot, rootfs, tmpDir, "A(uname)", a);

        // Тест B: sh
        List<String> b = new ArrayList<>();
        b.add("/bin/sh"); b.add("-c"); b.add("echo SH_OK");
        testLaunch(proot, rootfs, tmpDir, "B(sh)", b);

        // Тест C: bash
        List<String> c = new ArrayList<>();
        c.add("/bin/bash"); c.add("-c"); c.add("echo BASH_OK");
        testLaunch(proot, rootfs, tmpDir, "C(bash)", c);

        log("=== Диагностика завершена ===");
    }

    // Печатает существование/права/длину файла внутри rootfs
    private void checkFile(File rootfs, String rel) {
        File f = new File(rootfs, rel);
        log("Проверка " + rel +
                ": exists=" + f.exists() +
                " read=" + f.canRead() +
                " exec=" + f.canExecute() +
                " len=" + f.length() +
                " symlink=" + Files.isSymbolicLink(f.toPath()));
    }

    // Один тестовый запуск proot с гостевой командой
    private void testLaunch(File proot, File rootfs, File tmpDir,
                            String tag, List<String> guestCmd) throws Exception {
        List<String> cmd = new ArrayList<>();
        cmd.add(proot.getAbsolutePath());
        cmd.add("-r"); cmd.add(rootfs.getAbsolutePath());
        cmd.add("-b"); cmd.add("/dev");
        cmd.add("-b"); cmd.add("/proc");
        cmd.add("-b"); cmd.add("/sys");
        // Даём гостю writable /tmp
        cmd.add("-b"); cmd.add(tmpDir.getAbsolutePath() + ":/tmp");
        cmd.addAll(guestCmd);

        log("--- Тест " + tag + " ---");

        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.directory(rootfs);
        pb.redirectErrorStream(true);
        pb.environment().put("HOME", "/root");
        pb.environment().put("TERM", "xterm");
        pb.environment().put("PATH",
                "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
        // ВАЖНО: без этого proot не может создать временный файл
        pb.environment().put("PROOT_TMP_DIR", tmpDir.getAbsolutePath());

        Process p = pb.start();
        try (InputStream in = p.getInputStream()) {
            java.io.BufferedReader br =
                    new java.io.BufferedReader(new java.io.InputStreamReader(in));
            String line;
            while ((line = br.readLine()) != null) {
                log("[" + tag + "] " + line);
            }
        }
        int code = p.waitFor();
        log("Тест " + tag + " код выхода: " + code);
    }

    private File prepareProot() throws Exception {
        File libProot = new File(getApplicationInfo().nativeLibraryDir, "libproot.so");
        if (libProot.exists() && libProot.canExecute()) {
            return libProot;
        }

        File proot = new File(getFilesDir(), "proot");
        if (!proot.exists() || proot.length() == 0) {
            try (InputStream in = getAssets().open("proot_static");
                 FileOutputStream out = new FileOutputStream(proot)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
        }
        Os.chmod(proot.getAbsolutePath(), 0b111101101);
        return proot;
    }

    private void extractRootfs(File rootfs) throws Exception {
        rootfs.mkdirs();
        String destCanonical = rootfs.getCanonicalPath();
        int count = 0;

        try (InputStream raw = getAssets().open("debian-rootfs.tar.xz");
             XZCompressorInputStream xz =
                     new XZCompressorInputStream(new BufferedInputStream(raw, 1 << 20));
             TarArchiveInputStream tar = new TarArchiveInputStream(xz)) {

            TarArchiveEntry entry;
            while ((entry = (TarArchiveEntry) tar.getNextEntry()) != null) {
                String name = entry.getName();
                while (name.startsWith("./")) name = name.substring(2);
                while (name.startsWith("/")) name = name.substring(1);
                if (name.isEmpty()) continue;

                File out = new File(rootfs, name);
                if (!out.getCanonicalPath().startsWith(destCanonical)) continue;

                if (entry.isDirectory()) {
                    out.mkdirs();
                    safeChmod(out, entry.getMode() & 07777, true);
                } else if (entry.isSymbolicLink()) {
                    out.getParentFile().mkdirs();
                    if (out.exists()) out.delete();
                    try {
                        Os.symlink(entry.getLinkName(), out.getAbsolutePath());
                    } catch (Throwable t) {
                        log("symlink ошибка: " + name);
                    }
                } else if (entry.isLink()) {
                    // hardlink, при неудаче — копируем файл целиком
                    out.getParentFile().mkdirs();
                    String target = entry.getLinkName();
                    while (target.startsWith("./")) target = target.substring(2);
                    while (target.startsWith("/")) target = target.substring(1);
                    File targetFile = new File(rootfs, target);
                    if (targetFile.exists()) {
                        try {
                            Os.link(targetFile.getAbsolutePath(), out.getAbsolutePath());
                        } catch (Throwable t) {
                            copyFile(targetFile, out);
                            safeChmod(out, entry.getMode() & 07777, false);
                        }
                    }
                } else {
                    out.getParentFile().mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(out)) {
                        byte[] buf = new byte[65536];
                        int n;
                        while ((n = tar.read(buf)) > 0) fos.write(buf, 0, n);
                    }
                    safeChmod(out, entry.getMode() & 07777, false);
                }

                count++;
                if (count % 2000 == 0) log("Распаковано записей: " + count);
            }
        }
        log("Всего записей в rootfs: " + count);
    }

    private void copyFile(File src, File dst) throws Exception {
        try (FileInputStream in = new FileInputStream(src);
             FileOutputStream out = new FileOutputStream(dst)) {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
    }

    private void safeChmod(File f, int mode, boolean isDir) {
        try {
            int m = (mode != 0) ? mode : (isDir ? 0755 : 0644);
            Os.chmod(f.getAbsolutePath(), m);
        } catch (Throwable t) {
            f.setReadable(true, false);
            f.setWritable(true, false);
            f.setExecutable(true, false);
        }
    }

    private void deleteRecursively(File f) {
        File[] list = f.listFiles();
        if (list != null) for (File c : list) deleteRecursively(c);
        f.delete();
    }

    private String readFile(File f) {
        try {
            return new String(Files.readAllBytes(f.toPath())).trim();
        } catch (Throwable t) {
            return "";
        }
    }

    private void writeFile(File f, String text) {
        try (FileOutputStream fos = new FileOutputStream(f)) {
            fos.write(text.getBytes());
        } catch (Throwable t) {
            log("Не удалось записать маркер: " + t.getMessage());
        }
    }
}
