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
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    private static final String TAG = "SecondaryOS";
    private static final int INSTALL_VERSION = 1;

    private TextView logView;
    private Button startButton;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final java.util.concurrent.ExecutorService executor =
            Executors.newSingleThreadExecutor();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Строим простой интерфейс кодом, без layout-файла
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

    // Вывод строки на экран и в logcat
    private void log(String msg) {
        Log.i(TAG, msg);
        mainHandler.post(() -> logView.append(msg + "\n"));
    }

    private void startLinux() {
        startButton.setEnabled(false);
        executor.execute(() -> {
            try {
                runContainer();
            } catch (Throwable t) {
                log("✗ КРИТИЧЕСКАЯ ОШИБКА: " + t);
                Log.e(TAG, "fatal", t);
            } finally {
                mainHandler.post(() -> startButton.setEnabled(true));
            }
        });
    }

    private void runContainer() throws Exception {
        log("=== Начало диагностики ===");

        // 1. Готовим proot (предпочитаем libproot.so из nativeLibraryDir)
        File proot = prepareProot();
        log("proot путь: " + proot.getAbsolutePath());
        log("proot exists: " + proot.exists() +
                ", canExecute: " + proot.canExecute() +
                ", length: " + proot.length());

        if (!proot.exists() || proot.length() == 0) {
            log("✗ proot не найден или пустой");
            return;
        }

        // 2. Распаковываем rootfs, если ещё не распакован
        File rootfs = new File(getFilesDir(), "debian");
        File marker = new File(getFilesDir(), ".secondaryos_installed");

        String markerText = marker.exists() ? readFile(marker) : "";
        if (!markerText.equals(String.valueOf(INSTALL_VERSION)) || !rootfs.exists()) {
            log("Распаковываю rootfs (это может занять несколько минут)...");
            if (rootfs.exists()) deleteRecursively(rootfs);
            extractRootfs(rootfs);
            writeFile(marker, String.valueOf(INSTALL_VERSION));
            log("Rootfs распакован.");
        } else {
            log("Rootfs уже распакован, пропускаю.");
        }

        // 3. Запускаем контейнер с тестовой командой
        File tmpDir = new File(getFilesDir(), "tmp");
        tmpDir.mkdirs();

        List<String> cmd = new ArrayList<>();
        cmd.add(proot.getAbsolutePath());
        cmd.add("-r"); cmd.add(rootfs.getAbsolutePath());
        cmd.add("-b"); cmd.add("/dev");
        cmd.add("-b"); cmd.add("/proc");
        cmd.add("-b"); cmd.add("/sys");
        cmd.add("/bin/bash");
        cmd.add("-c");
        cmd.add("echo '=== КОНТЕЙНЕР ЖИВ ==='; uname -a; head -4 /etc/os-release; ls /");

        log("Запуск: " + String.join(" ", cmd));

        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.directory(rootfs);
        pb.redirectErrorStream(true); // stderr туда же, чтобы ошибки не пропали

        // Переменные окружения для контейнера
        pb.environment().put("HOME", "/root");
        pb.environment().put("TERM", "xterm");
        pb.environment().put("PATH",
                "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
        pb.environment().put("PROOT_TMP_DIR", tmpDir.getAbsolutePath());

        Process process = pb.start();

        // Читаем вывод контейнера построчно
        try (InputStream in = process.getInputStream()) {
            java.io.BufferedReader br =
                    new java.io.BufferedReader(new java.io.InputStreamReader(in));
            String line;
            while ((line = br.readLine()) != null) {
                log("[linux] " + line);
            }
        }

        int code = process.waitFor();
        log("Контейнер завершился, код: " + code);
        if (code != 0) {
            log("✗ Контейнер упал. Пришли скриншот — будем чинить.");
        }
    }

    // Ищем proot: сначала в nativeLibraryDir (libproot.so), иначе из assets в files/
    private File prepareProot() throws Exception {
        File libProot = new File(getApplicationInfo().nativeLibraryDir, "libproot.so");
        if (libProot.exists() && libProot.canExecute()) {
            log("Использую proot из nativeLibraryDir (libproot.so)");
            return libProot;
        }

        log("libproot.so не найден, копирую proot_static из assets...");
        File proot = new File(getFilesDir(), "proot");
        if (!proot.exists() || proot.length() == 0) {
            try (InputStream in = getAssets().open("proot_static");
                 FileOutputStream out = new FileOutputStream(proot)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
        }

        // Ставим права 0755 (rwxr-xr-x)
        Os.chmod(proot.getAbsolutePath(), 0b111101101);
        return proot;
    }

    // Распаковка debian-rootfs.tar.xz с сохранением прав, symlink и hardlink
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

                // Защита от выхода за пределы rootfs
                if (!out.getCanonicalPath().startsWith(destCanonical)) {
                    log("Пропускаю опасный путь: " + name);
                    continue;
                }

                if (entry.isDirectory()) {
                    out.mkdirs();
                    safeChmod(out, entry.getMode() & 07777, true);
                } else if (entry.isSymbolicLink()) {
                    out.getParentFile().mkdirs();
                    if (out.exists()) out.delete();
                    try {
                        Os.symlink(entry.getLinkName(), out.getAbsolutePath());
                    } catch (Throwable t) {
                        log("symlink ошибка: " + name + " -> " + t.getMessage());
                    }
                } else if (entry.isLink()) {
                    // hardlink
                    out.getParentFile().mkdirs();
                    String target = entry.getLinkName();
                    while (target.startsWith("./")) target = target.substring(2);
                    while (target.startsWith("/")) target = target.substring(1);
                    File targetFile = new File(rootfs, target);
                    if (targetFile.exists()) {
                        try {
                            Os.link(targetFile.getAbsolutePath(), out.getAbsolutePath());
                        } catch (Throwable t) {
                            log("hardlink ошибка: " + name + " -> " + t.getMessage());
                        }
                    }
                } else {
                    // Обычный файл
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

    // chmod с запасным вариантом, если Os.chmod недоступен
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
            return new String(java.nio.file.Files.readAllBytes(f.toPath())).trim();
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
