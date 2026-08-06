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
            File debianDir = new File(filesDir, "debian");
            File statusFile = new File(filesDir, "status.txt");
            File rootfsArchive = new File(filesDir, "debian-rootfs.tar");

            // Путь к proot в nativeLibraryDir
            String prootPath = getApplicationInfo().nativeLibraryDir + "/libproot.so";

            updateStatus("Проверка файлов...");
            log("=== Начало диагностики ===");
            log("nativeLibraryDir: " + getApplicationInfo().nativeLibraryDir);
            log("proot путь: " + prootPath);
            
            File prootFile = new File(prootPath);
            log("proot exists: " + prootFile.exists());
            log("proot canRead: " + prootFile.canRead());
            log("proot canExecute: " + prootFile.canExecute());
            log("proot length: " + prootFile.length());
            
            if (prootFile.exists()) {
                try (InputStream is = new java.io.FileInputStream(prootFile)) {
                    byte[] header = new byte[4];
                    is.read(header);
                    boolean isElf = (header[0] == 0x7f && header[1] == 0x45 && 
                                   header[2] == 0x4c && header[3] == 0x46);
                    log("proot is ELF: " + isElf);
                } catch (Exception e) {
                    log("Ошибка чтения proot: " + e.getMessage());
                }
            }

            // Проверяем assets
            String[] assets = getAssets().list("");
            if (assets != null) {
                log("Файлы в assets: " + String.join(", ", assets));
            }

            // 1. Копируем rootfs из assets
            if (!rootfsArchive.exists()) {
                updateStatus("Копирование rootfs...");
                copyAssetToFile("debian-rootfs.tar", rootfsArchive);
                log("✓ rootfs скопирован, размер: " + rootfsArchive.length());
            } else {
                log("✓ rootfs уже на месте, размер: " + rootfsArchive.length());
            }

            // 2. Распаковка rootfs
            if (!debianDir.exists() || !new File(debianDir, "bin/sh").exists()) {
                updateStatus("Распаковка Debian...");
                debianDir.mkdirs();
                
                log("Распаковка tar в: " + debianDir.getAbsolutePath());
                ProcessBuilder pb = new ProcessBuilder(
                    "/system/bin/tar", "-xf",
                    rootfsArchive.getAbsolutePath(),
                    "-C", debianDir.getAbsolutePath()
                );
                pb.redirectErrorStream(true);
                Process tarProcess = pb.start();
                
                BufferedReader tarReader = new BufferedReader(
                    new InputStreamReader(tarProcess.getInputStream()));
                String tarLine;
                while ((tarLine = tarReader.readLine()) != null) {
                    log("[TAR] " + tarLine);
                }
                
                int tarResult = tarProcess.waitFor();
                if (tarResult == 0) {
                    log("✓ Debian rootfs распакован");
                    log("Содержимое debian/bin: " + 
                        java.util.Arrays.toString(new File(debianDir, "bin").list()));
                } else {
                    log("✗ tar error: " + tarResult);
                    updateStatus("Ошибка распаковки!");
                    return;
                }
            } else {
                log("✓ Debian rootfs уже распакован");
            }

            // 3. ЗАПУСК PROOT
            updateStatus("Запуск контейнера...");
            
            // УПРОЩЁННАЯ КОМАНДА - просто stub_proot без /bin/sh -c
            String[] cmd = {
                prootPath,
                "-r", debianDir.getAbsolutePath(),
                "-b", "/dev", "-b", "/proc", "-b", "/sys",
                "/bin/sh"  // stub_proot проигнорирует это и сам создаст status.txt
            };

            log("Запуск команды: " + String.join(" ", cmd));
            
            ProcessBuilder pb = new ProcessBuilder(cmd);
            
            // ВАЖНО: устанавливаем working directory туда, где должен быть status.txt
            pb.directory(filesDir);
            
            log("Working directory: " + filesDir.getAbsolutePath());
            log("status.txt будет создан в: " + statusFile.getParentFile().getAbsolutePath());
            
            pb.redirectErrorStream(true);
            Process process = pb.start();

            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                log("[PROOT] " + line);
                output.append(line).append("\n");
            }

            int exitCode = process.waitFor();
            log("Процесс завершён с кодом: " + exitCode);

            // 4. Проверка результата
            // Ждём немного, чтобы файл успел создаться
            Thread.sleep(500);
            
            if (statusFile.exists()) {
                java.util.Scanner scanner = new java.util.Scanner(statusFile);
                String content = scanner.useDelimiter("\\A").hasNext()
                    ? scanner.useDelimiter("\\A").next() : "";
                scanner.close();

                log("status.txt содержит: '" + content.trim() + "'");

                if (content.trim().equals("CONTAINER_ALIVE")) {
                    updateStatus("УСПЕХ: Контейнер жив!");
                    log(">>> ЭТАП 0 ПРОЙДЕН! <<<");
                } else {
                    updateStatus("ОШИБКА: неверный статус");
                }
            } else {
                updateStatus("ОШИБКА: status.txt не создан");
                log("Полный вывод proot: " + output.toString());
                
                // Дополнительная диагностика
                log("=== Дополнительная диагностика ===");
                log("statusFile path: " + statusFile.getAbsolutePath());
                log("statusFile parent exists: " + statusFile.getParentFile().exists());
                log("statusFile parent writable: " + statusFile.getParentFile().canWrite());
                log("filesDir list: " + java.util.Arrays.toString(filesDir.list()));
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
