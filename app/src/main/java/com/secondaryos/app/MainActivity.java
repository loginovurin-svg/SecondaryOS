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
            File cacheDir = getCacheDir();  // Используем cache для proot
            File prootFile = new File(cacheDir, "proot");  // proot в cache!
            File debianDir = new File(filesDir, "debian");
            File statusFile = new File(filesDir, "status.txt");
            File rootfsArchive = new File(filesDir, "debian-rootfs.tar");

            updateStatus("Проверка файлов...");
            log("=== Начало диагностики ===");
            log("Cache dir: " + cacheDir.getAbsolutePath());

            // ДИАГНОСТИКА: проверяем, что есть в assets
            log("Проверка assets приложения...");
            String[] assets = getAssets().list("");
            if (assets != null) {
                log("Файлы в assets: " + String.join(", ", assets));
            } else {
                log(" Не удалось получить список assets");
            }

            // 1. Копирование proot В CACHE директорию
            updateStatus("Копирование proot в cache...");
            copyAssetToFile("proot", prootFile);
            
            // Выставляем права ЧЕРЕЗ chmod
            Process chmod = Runtime.getRuntime().exec("chmod 755 " + prootFile.getAbsolutePath());
            int chmodResult = chmod.waitFor();
            log("chmod результат: " + chmodResult);
            log("proot файл: " + prootFile.getAbsolutePath());
            log("proot exists: " + prootFile.exists() + ", canRead: " + prootFile.canRead() + ", canExecute: " + prootFile.canExecute());
            log("✓ proot скопирован в cache");

            // 2. Проверка и распаковка rootfs архива
            if (!rootfsArchive.exists()) {
                updateStatus("Копирование rootfs...");
                copyAssetToFile("debian-rootfs.tar", rootfsArchive);
                log("✓ rootfs архив скопирован, размер: " + rootfsArchive.length() + " байт");
            } else {
                log("✓ rootfs архив уже на месте");
            }

            // 3. Распаковка rootfs
            if (!debianDir.exists() || !new File(debianDir, "bin/sh").exists()) {
                updateStatus("Распаковка Debian...");
                debianDir.mkdirs();
                
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

            // 4. Запуск proot ИЗ CACHE директории
            updateStatus("Запуск контейнера...");
            
            String[] cmd = {
                prootFile.getAbsolutePath(),  // proot из cache!
                "-r", debianDir.getAbsolutePath(),
                "-b", "/dev", "-b", "/proc", "-b", "/sys",
                "/bin/sh", "-c", "echo CONTAINER_ALIVE > " + statusFile.getAbsolutePath() + " && echo 'Minimal shell working'"
            };

            log("Запуск команды: " + String.join(" ", cmd));
            
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.directory(cacheDir);  // Устанавливаем working directory
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
                log("Полный вывод: " + output.toString());
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
