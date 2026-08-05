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
            File rootfsArchive = new File(filesDir, "debian-rootfs.tar.gz");

            updateStatus("Проверка файлов...");
            log("=== Начало диагностики ===");
            log("filesDir: " + filesDir.getAbsolutePath());
            log("filesDir exists: " + filesDir.exists() + ", writable: " + filesDir.canWrite());

            // 1. Проверка proot
            if (!prootFile.exists()) {
                updateStatus("Распаковка proot...");
                try {
                    copyAssetToFile("proot", prootFile);
                    Process chmod = Runtime.getRuntime().exec("chmod 700 " + prootFile.getAbsolutePath());
                    chmod.waitFor();
                    log("✓ proot распакован и chmod 700 выполнен");
                } catch (Exception e) {
                    log("✗ Ошибка копирования proot: " + e.getMessage());
                    updateStatus("Сбой proot!");
                    return;
                }
            } else {
                log("✓ proot уже на месте");
            }

            // 2. Проверка rootfs архива
            if (!rootfsArchive.exists()) {
                updateStatus("Распаковка rootfs...");
                log("Копирование debian-rootfs.tar.gz из assets...");
                try {
                    copyAssetToFile("debian-rootfs.tar.gz", rootfsArchive);
                    log("✓ rootfs архив скопирован, размер: " + rootfsArchive.length() + " байт");
                } catch (Exception e) {
                    log(" КРИТИЧЕСКАЯ ОШИБКА: debian-rootfs.tar.gz не найден в assets!");
                    log("✗ Ошибка: " + e.getMessage());
                    updateStatus("Нет rootfs!");
                    return;
                }
            } else {
                log("✓ rootfs архив уже на месте, размер: " + rootfsArchive.length());
            }

            // 3. Распаковка rootfs
            if (!debianDir.exists() || !new File(debianDir, "bin/sh").exists()) {
                updateStatus("Распаковка Debian...");
                debianDir.mkdirs();
                log("Распаковка tar.gz в " + debianDir.getAbsolutePath());
                
                ProcessBuilder pb = new ProcessBuilder(
                    "/system/bin/tar", "-xzf", 
                    rootfsArchive.getAbsolutePath(), 
                    "-C", debianDir.getAbsolutePath()
                );
                Process tarProcess = pb.start();
                
                // Читаем ошибки tar
                BufferedReader errorReader = new BufferedReader(new InputStreamReader(tarProcess.getErrorStream()));
                String line;
                while ((line = errorReader.readLine()) != null) {
                    log("[TAR ERROR] " + line);
                }
                
                int tarResult = tarProcess.waitFor();
                if (tarResult == 0) {
                    log("✓ Debian rootfs распакован");
                    log("Содержимое debian/bin: " + java.util.Arrays.toString(new File(debianDir, "bin").list()));
                } else {
                    log("✗ ОШИБКА: tar вернул код " + tarResult);
                    updateStatus("Ошибка распаковки!");
                    return;
                }
            } else {
                log("✓ Debian rootfs уже распакован");
            }

            // 4. Запуск proot
            updateStatus("Запуск контейнера...");
            String[] cmd = {
                prootFile.getAbsolutePath(),
                "-r", debianDir.getAbsolutePath(),
                "-b", "/dev", "-b", "/proc", "-b", "/sys",
                "/bin/sh"
            };

            log("Запуск команды: " + String.join(" ", cmd));
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            // Читаем вывод
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            while ((line = reader.readLine()) != null) {
                log("[PROOT] " + line);
                output.append(line).append("\n");
            }
            
            int exitCode = process.waitFor();
            log("Процесс завершён с кодом: " + exitCode);

            // 5. Проверка результата
            if (statusFile.exists()) {
                java.util.Scanner scanner = new java.util.Scanner(statusFile);
                String content = scanner.useDelimiter("\\A").next();
                scanner.close();
                
                if (content.trim().equals("CONTAINER_ALIVE")) {
                    updateStatus("УСПЕХ: Контейнер жив!");
                    log(">>> ЭТАП 0 ПРОЙДЕН! <<<");
                } else {
                    updateStatus("ОШИБКА: Неверный статус");
                    log("status.txt содержит: " + content);
                }
            } else {
                updateStatus("ОШИБКА: status.txt не создан");
                log("Вывод proot: " + output.toString());
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
