package com.secondaryos.app;

import android.app.Activity;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PrintWriter;

public class MainActivity extends Activity {

    private TextView outputTextView;
    private EditText inputEditText;
    private Button sendButton;

    private Process shellProcess;
    private PrintWriter shellWriter;
    private Thread outputReaderThread;

    private File rootfsDir;
    private File qemuBinary;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        rootfsDir = new File(getFilesDir(), "debian-rootfs");
        qemuBinary = new File(getFilesDir(), "qemu-aarch64");

        outputTextView = new TextView(this);
        outputTextView.setText("SecondaryOS — инициализация...\n");
        outputTextView.setTextColor(0xFF00FF41);
        outputTextView.setBackgroundColor(0xFF0A0A0A);
        outputTextView.setPadding(16, 16, 16, 16);
        outputTextView.setTextSize(13);
        outputTextView.setTypeface(android.graphics.Typeface.MONOSPACE);

        inputEditText = new EditText(this);
        inputEditText.setHint("Введите команду (ls /, apt update...)");
        inputEditText.setTextColor(0xFFFFFFFF);
        inputEditText.setHintTextColor(0xFF888888);
        inputEditText.setBackgroundColor(0xFF1A1A1A);

        sendButton = new Button(this);
        sendButton.setText("ВЫПОЛНИТЬ");

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setBackgroundColor(0xFF0A0A0A);
        layout.setPadding(16, 16, 16, 16);

        LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1.0f);
        LinearLayout.LayoutParams inputParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);

        layout.addView(outputTextView, textParams);
        layout.addView(inputEditText, inputParams);
        layout.addView(sendButton, inputParams);

        setContentView(layout);

        sendButton.setOnClickListener(v -> {
            String cmd = inputEditText.getText().toString();
            if (shellWriter != null && !cmd.isEmpty()) {
                shellWriter.println(cmd);
                shellWriter.flush();
                inputEditText.setText("");
            } else {
                logToUi("⚠ Оболочка ещё не запущена или команда пустая.");
            }
        });

        new Thread(this::bootstrap).start();
    }

    private void bootstrap() {
        extractRootfs();
        prepareQemu();
        runDiagnostics();

        try { Thread.sleep(500); } catch (InterruptedException ignored) {}

        startInteractiveShell();
    }

    private void extractRootfs() {
        // Проверяем, распакован ли уже rootfs
        if (rootfsDir.exists() && rootfsDir.isDirectory()) {
            String[] files = rootfsDir.list();
            if (files != null && files.length > 0) {
                logToUi("✅ rootfs уже распакован (" + files.length + " объектов), пропускаем.");
                return;
            }
        }

        logToUi("⚙ Распаковка rootfs из APK (30-90 сек)...");
        rootfsDir.mkdirs();

        try {
            File tempArchive = new File(getCacheDir(), "debian-rootfs.tar.xz");
            
            // Копируем архив из assets
            try (InputStream is = getAssets().open("debian-rootfs.tar.xz");
                 FileOutputStream fos = new FileOutputStream(tempArchive)) {
                byte[] buffer = new byte[65536];
                int read;
                while ((read = is.read(buffer)) != -1) {
                    fos.write(buffer, 0, read);
                }
            }
            logToUi("  архив скопирован в cache, запускаем распаковку...");

            // Пробуем несколько методов распаковки
            String[] extractCommands = {
                // Метод 1: tar с автоматическим распознаванием (Android toybox)
                "tar -xJf '" + tempArchive.getAbsolutePath() + "' -C '" + rootfsDir.getAbsolutePath() + "'",
                // Метод 2: xz + tar через pipe
                "xz -d -c '" + tempArchive.getAbsolutePath() + "' | tar -xf - -C '" + rootfsDir.getAbsolutePath() + "'",
                // Метод 3: unxz + tar
                "unxz -c '" + tempArchive.getAbsolutePath() + "' | tar -xf - -C '" + rootfsDir.getAbsolutePath() + "'"
            };
            
            boolean success = false;
            for (int i = 0; i < extractCommands.length; i++) {
                logToUi("  пробуем метод " + (i+1) + "...");
                
                ProcessBuilder pb = new ProcessBuilder("sh", "-c", extractCommands[i]);
                pb.redirectErrorStream(true);
                Process extractProcess = pb.start();
                
                // Читаем вывод для отладки
                BufferedReader reader = new BufferedReader(new InputStreamReader(extractProcess.getInputStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    logToUi("    " + line);
                }
                
                int exitCode = extractProcess.waitFor();
                
                // Проверяем результат
                if (exitCode == 0 && rootfsDir.list() != null && rootfsDir.list().length > 0) {
                    success = true;
                    logToUi("  ✅ метод " + (i+1) + " сработал!");
                    break;
                } else {
                    logToUi("   метод " + (i+1) + " не сработал (код: " + exitCode + "), пробуем следующий...");
                    // Очищаем директорию для следующей попытки
                    deleteDirectory(rootfsDir);
                    rootfsDir.mkdirs();
                }
            }
            
            // Удаляем временный архив
            tempArchive.delete();
            
            if (!success) {
                logToUi("❌ все методы распаковки не сработали");
                logToUi("  проверьте, что в assets лежит валидный debian-rootfs.tar.xz");
            } else {
                logToUi("✅ rootfs распакован (" + rootfsDir.list().length + " объектов).");
            }

        } catch (Exception e) {
            logToUi("❌ ошибка распаковки: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void prepareQemu() {
        if (qemuBinary.exists() && qemuBinary.canExecute()) {
            logToUi("✅ qemu-aarch64 уже готов.");
            return;
        }

        logToUi("⚙ подготовка qemu-aarch64...");
        try {
            try (InputStream is = getAssets().open("qemu-aarch64");
                 FileOutputStream fos = new FileOutputStream(qemuBinary)) {
                byte[] buffer = new byte[65536];
                int read;
                while ((read = is.read(buffer)) != -1) {
                    fos.write(buffer, 0, read);
                }
            }
            Runtime.getRuntime().exec(new String[]{"chmod", "700", qemuBinary.getAbsolutePath()}).waitFor();
            logToUi("✅ qemu-aarch64 готов.");
        } catch (Exception e) {
            logToUi("❌ ошибка подготовки QEMU: " + e.getMessage());
        }
    }

    private void runDiagnostics() {
        if (rootfsDir.exists() && rootfsDir.list() != null && rootfsDir.list().length > 0) {
            logToUi("[OK] debian-rootfs: " + rootfsDir.list().length + " объектов");
        } else {
            logToUi("[FAIL] debian-rootfs отсутствует или пуст — оболочка не запустится.");
        }

        if (qemuBinary.exists() && qemuBinary.canExecute()) {
            logToUi("[OK] qemu-aarch64 готов к запуску.");
        } else {
            logToUi("[FAIL] qemu-aarch64 отсутствует.");
        }
    }

    private void startInteractiveShell() {
        if (!rootfsDir.exists() || rootfsDir.list() == null || rootfsDir.list().length == 0) {
            logToUi("❌ невозможно запустить оболочку: rootfs не распакован.");
            return;
        }

        if (!qemuBinary.exists()) {
            logToUi(" невозможно запустить оболочку: qemu-aarch64 не найден.");
            return;
        }

        logToUi("🚀 запуск оболочки Debian через QEMU user-mode...");

        try {
            String[] command = {
                    qemuBinary.getAbsolutePath(),
                    "-L", rootfsDir.getAbsolutePath(),
                    "-E", "HOME=/root",
                    "-E", "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                    "-E", "TERM=xterm-256color",
                    rootfsDir.getAbsolutePath() + "/bin/sh"
            };

            ProcessBuilder pb = new ProcessBuilder(command);
            pb.directory(rootfsDir);
            pb.redirectErrorStream(true);

            shellProcess = pb.start();

            outputReaderThread = new Thread(this::readShellOutput);
            outputReaderThread.setDaemon(true);
            outputReaderThread.start();

            shellWriter = new PrintWriter(shellProcess.getOutputStream(), true);

            logToUi("✅ оболочка запущена. введите 'ls /' для проверки.");

        } catch (Exception e) {
            logToUi("❌ ошибка запуска оболочки: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void readShellOutput() {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(shellProcess.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                logToUi(line);
            }
        } catch (Exception e) {
            logToUi("[поток вывода закрыт: " + e.getMessage() + "]");
        }
    }

    private void logToUi(final String message) {
        runOnUiThread(() -> outputTextView.append(message + "\n"));
    }
    
    // Вспомогательный метод для рекурсивного удаления директории
    private void deleteDirectory(File dir) {
        if (dir.exists()) {
            File[] files = dir.listFiles();
            if (files != null) {
                for (File file : files) {
                    if (file.isDirectory()) {
                        deleteDirectory(file);
                    } else {
                        file.delete();
                    }
                }
            }
            dir.delete();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (shellProcess != null) {
            shellProcess.destroy();
        }
        if (shellWriter != null) {
            shellWriter.close();
        }
        if (outputReaderThread != null) {
            outputReaderThread.interrupt();
        }
    }
}
