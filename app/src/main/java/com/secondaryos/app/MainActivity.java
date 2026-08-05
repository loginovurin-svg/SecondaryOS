package com.secondaryos.app;

import android.os.Bundle;
import android.util.Log;
import android.widget.Button;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "SecondaryOS";
    private TextView tvStatus;
    private TextView tvLogs;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        tvStatus = findViewById(R.id.tvStatus);
        tvLogs = findViewById(R.id.tvLogs);
        Button btnStart = findViewById(R.id.btnStartLinux);

        btnStart.setOnClickListener(v -> new Thread(this::runLinuxContainer).start());
    }

    private void log(String message) {
        runOnUiThread(() -> {
            tvLogs.append(message + "\n");
            Log.d(TAG, message);
        });
    }

    private void updateStatus(String status) {
        runOnUiThread(() -> tvStatus.setText("Статус: " + status));
    }

    private void runLinuxContainer() {
        try {
            File filesDir = getFilesDir();
            File prootFile = new File(filesDir, "proot");
            File debianDir = new File(filesDir, "debian");
            File statusFile = new File(filesDir, "status.txt");
            // Android AAPT распаковывает .gz, поэтому файл называется .tar
            File rootfsArchive = new File(filesDir, "debian-rootfs.tar");

            updateStatus("Проверка файлов...");
            log("=== Начало диагностики ===");

            // ДИАГНОСТИКА: проверяем, что есть в assets
            log("Проверка assets приложения...");
            String[] assets = getAssets().list("");
            if (assets != null) {
                log("Файлы в assets: " + String.join(", ", assets));
            } else {
                log("✗ Не удалось получить список assets");
            }

            // 1. Проверка и распаковка proot
            if (!prootFile.exists()) {
                updateStatus("Распаковка proot...");
                copyAssetToFile("proot", prootFile);
                Process chmod = Runtime.getRuntime().exec("chmod 700 " + prootFile.getAbsolutePath());
                chmod.waitFor();
                log("✓ proot распакован и chmod 700 выполнен");
            } else {
                log("✓ proot уже на месте");
            }

            // 2. Проверка и распаковка rootfs архива
            if (!rootfsArchive.exists()) {
                updateStatus("Копирование rootfs...");
                try {
                    copyAssetToFile("debian-rootfs.tar", rootfsArchive);
                    log("✓ rootfs архив скопирован, размер: " + rootfsArchive.length() + " байт");
                } catch (Exception e) {
                    log("✗ ОШИБКА копирования rootfs: " + e.getMessage());
                    log("Возможно, файл не существует в assets");
                    updateStatus("Нет rootfs в APK!");
                    return;
                }
            } else {
                log("✓ rootfs архив уже на месте");
            }

            // 3. Распаковка rootfs
            if (!debianDir.exists() || !new File(debianDir, "bin/sh").exists()) {
                updateStatus("Распаковка Debian...");
                debianDir.mkdirs();
                
                // Используем -xf вместо -xzf (файл уже не сжат)
                ProcessBuilder pb = new ProcessBuilder(
                    "/system/bin/tar", "-xf", 
                    rootfsArchive.getAbsolutePath(), 
                    "-C", debianDir.getAbsolutePath()
                );
                Process tarProcess = pb.start();
                
                BufferedReader errorReader = new BufferedReader(new InputStreamReader(tarProcess.getErrorStream()));
                String errLine;
                while ((errLine = errorReader.readLine()) != null) {
                    log("[TAR WARN] " + errLine);
                }
                
                int tarResult = tarProcess.waitFor();
                if (tarResult == 0) {
                    log("✓ Debian rootfs распакован");
                } else {
                    log("✗ ОШИБКА: tar вернул код " + tarResult);
                    updateStatus("Ошибка распаковки!");
                    return;
                }
            } else {
                log("✓ Debian rootfs уже распакован");
            }

            // 4. Запуск proot ЧЕРЕЗ /system/bin/sh -c (обход SELinux на Samsung)
            updateStatus("Запуск контейнера...");
            
            // Формируем команду proot
            String prootPath = prootFile.getAbsolutePath();
            String rootfsPath = debianDir.getAbsolutePath();
            String statusPath = statusFile.getAbsolutePath();
            
            // Оборачиваем proot в sh -c для обхода SELinux
            String prootCmd = prootPath + 
                " -r " + rootfsPath +
                " -b /dev -b /proc -b /sys" +
                " /bin/sh -c \"echo CONTAINER_ALIVE > " + statusPath + " && echo 'Minimal shell working'\"";
            
            String[] cmd = {
                "/system/bin/sh", "-c", prootCmd
            };

            log("Запуск через sh: " + prootCmd);
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            // Читаем вывод
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                log("[PROOT] " + line);
                output.append(line).append("\n");
            }
            
            int exitCode = process.waitFor();
            log("Процесс завершён с кодом: " + exitCode);

            // 5. Проверка результата
            if (statusFile.exists()) {
                java.util.Scanner scanner = new java.util.Scanner(statusFile);
                String content = scanner.useDelimiter("\\A").hasNext() ? scanner.useDelimiter("\\A").next() : "";
                scanner.close();
                
                if (content.trim().equals("CONTAINER_ALIVE")) {
                    updateStatus("УСПЕХ: Контейнер жив!");
                    log(">>> ЭТАП 0 ПРОЙДЕН! <<<");
                } else {
                    updateStatus("ОШИБКА: Неверный статус");
                    log("status.txt содержит: '" + content + "'");
                }
            } else {
                updateStatus("ОШИБКА: status.txt не создан");
                log("Полный вывод proot: " + output.toString());
            }

        } catch (Exception e) {
            log("✗ КРИТИЧЕСКАЯ ОШИБКА: " + e.getMessage());
            updateStatus("Сбой!");
            e.printStackTrace();
        }
    }

    private void copyAssetToFile(String assetName, File outputFile) throws Exception {
        try (InputStream in = getAssets().open(assetName);
             FileOutputStream out = new FileOutputStream(outputFile)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.write(buffer, 0, read);
            }
        }
    }
}
