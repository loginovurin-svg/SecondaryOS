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

            // 1. Распаковка proot
            updateStatus("Распаковка proot...");
            if (!prootFile.exists()) {
                copyAssetToFile("proot", prootFile);
                // Выставляем права на исполнение (критично для Android)
                Runtime.getRuntime().exec("chmod 700 " + prootFile.getAbsolutePath()).waitFor();
                log("proot распакован и chmod 700 выполнен.");
            } else {
                log("proot уже на месте.");
            }

            // 2. Распаковка rootfs
            updateStatus("Распаковка Debian rootfs (может занять время)...");
            if (!debianDir.exists() || !new File(debianDir, "bin/bash").exists()) {
                debianDir.mkdirs();
                File rootfsArchive = new File(filesDir, "debian-rootfs.tar.gz");
                if (!rootfsArchive.exists()) {
                    copyAssetToFile("debian-rootfs.tar.gz", rootfsArchive);
                }
                
                // Используем системный tar для распаковки
                Process tarProcess = Runtime.getRuntime().exec(new String[]{
                        "/system/bin/tar", "-xzf", rootfsArchive.getAbsolutePath(), "-C", debianDir.getAbsolutePath()
                });
                int tarResult = tarProcess.waitFor();
                if (tarResult == 0) {
                    log("Debian rootfs успешно распакован.");
                } else {
                    log("ОШИБКА: tar вернул код " + tarResult);
                    updateStatus("Ошибка распаковки!");
                    return;
                }
            } else {
                log("Debian rootfs уже распакован.");
            }

            // 3. Запуск proot
            updateStatus("Запуск контейнера...");
            String prootCmd = prootFile.getAbsolutePath();
            String rootfsPath = debianDir.getAbsolutePath();
            
            // Команда: proot -r <rootfs> -b /dev -b /proc -b /sys /bin/bash -c "echo CONTAINER_ALIVE > <status_file>"
            String[] cmd = {
                    prootCmd,
                    "-r", rootfsPath,
                    "-b", "/dev", "-b", "/proc", "-b", "/sys",
                    "/bin/bash", "-c", "echo CONTAINER_ALIVE > " + statusFile.getAbsolutePath()
            };

            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            // Читаем вывод
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            String line;
            while ((line = reader.readLine()) != null) {
                log("[PROOT] " + line);
            }
            
            int exitCode = process.waitFor();
            log("Процесс proot завершен с кодом: " + exitCode);

            // 4. Проверка жизни
            if (statusFile.exists()) {
                // Читаем файл статуса через Java, чтобы не зависеть от cat внутри proot
                java.util.Scanner scanner = new java.util.Scanner(statusFile);
                String content = scanner.useDelimiter("\\A").next();
                scanner.close();
                
                if (content.trim().equals("CONTAINER_ALIVE")) {
                    updateStatus("УСПЕХ: Контейнер жив!");
                    log(">>> ЭТАП 0 ПРОЙДЕН: Контейнер успешно выполнил команду. <<<");
                } else {
                    updateStatus("ОШИБКА: Неверный статус");
                    log("Содержимое status.txt: " + content);
                }
            } else {
                updateStatus("ОШИБКА: status.txt не создан");
            }

        } catch (Exception e) {
            log("КРИТИЧЕСКАЯ ОШИБКА: " + e.getMessage());
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
