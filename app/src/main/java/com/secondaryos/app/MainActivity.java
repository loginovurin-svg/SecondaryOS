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
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    private static final String TAG = "SecondaryOS";
    private static final int INSTALL_VERSION = 2;

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
        log("=== Этап 0: диагностика bash ===");

        File proot = prepareProot();
        log("proot: exists=" + proot.exists() + " exec=" + proot.canExecute());

        File rootfs = new File(getFilesDir(), "debian");
        File marker = new File(getFilesDir(), ".secondaryos_installed");
        String markerText = marker.exists() ? readFile(marker) : "";

        if (!markerText.equals(String.valueOf(INSTALL_VERSION)) || !rootfs.exists()) {
            log("Распаковываю rootfs...");
            if (rootfs.exists()) deleteRecursively(rootfs);
            extractRootfs(rootfs);
            writeFile(marker, String.valueOf(INSTALL_VERSION));
        } else {
            log("Rootfs уже распакован.");
        }

        File tmpDir = new File(getFilesDir(), "tmp");
        tmpDir.mkdirs();

        // Тест A: uname (обычный)
        List<String> a = new ArrayList<>();
        a.add("/usr/bin/uname"); a.add("-a");
        testLaunch(proot, rootfs, tmpDir, "A", a, 0);

        // Тест B: sh (обычный)
        List<String> b = new ArrayList<>();
        b.add("/bin/sh"); b.add("-c"); b.add("echo SH_OK");
        testLaunch(proot, rootfs, tmpDir, "B", b, 0);

        // Тест C: bash с ПОЛНЫМ verbose-логом, хвост на экран
        List<String> c = new ArrayList<>();
        c.add("/bin/bash"); c.add("-c"); c.add("echo BASH_OK");
        testLaunch(proot, rootfs, tmpDir, "C", c, 9);

        log("=== Готово. Нужен ХВОСТ теста C ===");
    }

    // verboseLevel=0: вывод напрямую.
    // verboseLevel>0: добавляет -v N, пишет всё в файл,
    // на экран — последние 40 строк.
    private void testLaunch(File proot, File rootfs, File tmpDir,
                            String tag, List<String> guestCmd,
                            int verboseLevel) throws Exception {
        List<String> cmd = new ArrayList<>();
        cmd.add(proot.getAbsolutePath());
        if (verboseLevel > 0) {
            cmd.add("-v");
            cmd.add(String.valueOf(verboseLevel));
        }
        cmd.add("-r"); cmd.add(rootfs.getAbsolutePath());
        cmd.add("-b"); cmd.add("/dev");
        cmd.add("-b"); cmd.add("/proc");
        cmd.add("-b"); cmd.add("/sys");
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
        pb.environment().put("PROOT_TMP_DIR", tmpDir.getAbsolutePath());

        Process p = pb.start();

        if (verboseLevel > 0) {
            File outFile = new File(getFilesDir(), "proot_log_" + tag + ".txt");
            Deque<String> tail = new ArrayDeque<>();
            int total = 0;
            try (BufferedWriter bw = new BufferedWriter(new FileWriter(outFile));
                 BufferedReader br = new BufferedReader(
                         new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = br.readLine()) != null) {
                    bw.write(line);
                    bw.newLine();
                    total++;
                    tail.addLast(line);
                    if (tail.size() > 40) tail.removeFirst();
                }
            }
            int code = p.waitFor();
            log("Тест " + tag + " код: " + code + ", строк: " + total);
            log("--- ХВОСТ теста " + tag + " ---");
            for (String l : tail) log("[" + tag + "] " + l);
        } else {
            try (BufferedReader br = new BufferedReader(
                    new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = br.readLine()) != null) {
                    log("[" + tag + "] " + line);
                }
            }
            int code = p.waitFor();
            log("Тест " + tag + " код выхода: " + code);
        }
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
