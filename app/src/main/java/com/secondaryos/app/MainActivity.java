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

    private Process process;
    private PrintWriter shellWriter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Простой UI: вывод, поле ввода, кнопка
        outputTextView = new TextView(this);
        outputTextView.setText("Инициализация SecondaryOS...\n");
        outputTextView.setTextColor(0xFFFFFFFF);
        outputTextView.setBackgroundColor(0xFF1E1E1E);
        outputTextView.setPadding(16, 16, 16, 16);

        inputEditText = new EditText(this);
        inputEditText.setHint("Введите команду (например, ls /)");
        inputEditText.setTextColor(0xFFFFFFFF);
        inputEditText.setHintTextColor(0xFF888888);

        sendButton = new Button(this);
        sendButton.setText("ВЫПОЛНИТЬ");

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setBackgroundColor(0xFF1E1E1E);
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

        // Обработчик кнопки
        sendButton.setOnClickListener(v -> {
            String cmd = inputEditText.getText().toString();
            if (shellWriter != null && !cmd.isEmpty()) {
                shellWriter.println(cmd);
                shellWriter.flush();
                inputEditText.setText("");
            } else {
                logToUi("⚠️ Оболочка не запущена или команда пустая.");
            }
        });

        // Запускаем всё в фоне, чтобы не блокировать UI
        new Thread(this::bootstrap).start();
    }

    /**
     * Главная последовательность запуска:
     * 1. Распаковать rootfs из assets
     * 2. Подготовить QEMU из assets
     * 3. Запустить оболочку
     */
    private void bootstrap() {
        extractRootfs();
        prepareQemu();
        runDiagnostics();
        
        // Небольшая задержка перед запуском оболочки
        try { Thread.sleep(500); } catch (InterruptedException ignored) {}
        
        startInteractiveShell();
    }

    /**
     * Распаковка debian-rootfs.tar.gz из assets во внутреннюю память.
     * Android toybox поддерживает tar -xzf, поэтому xz не нужен.
     */
    private void extractRootfs() {
        File rootfsDir = new File(getFilesDir(), "debian-rootfs");
        
        // Если уже распакован и не пуст — пропускаем
        if (rootfsDir.exists() && rootfsDir.isDirectory()) {
            String[] files = rootfsDir.list();
            if (files != null && files.length > 0) {
                logToUi("✅ Rootfs уже распакован, пропускаем.");
                return;
            }
        }

        logToUi(" Распаковка rootfs из APK (это займёт 30-60 сек)...");
        rootfsDir.mkdirs();

        try {
            // Копируем архив из assets во временный файл
            File tempArchive = new File(getCacheDir(), "debian-rootfs.tar.gz");
            try (InputStream is = getAssets().open("debian-rootfs.tar.gz");
                 FileOutputStream fos = new FileOutputStream(tempArchive)) {
                byte[] buffer = new byte[65536];
                int read;
                while ((read = is.read(buffer)) != -1) {
                    fos.write(buffer, 0, read);
                }
            }
            logToUi("Архив скопирован, запускаем распаковку...");

            // Распаковываем через системный tar (toybox в Android поддерживает gzip)
            ProcessBuilder pb = new ProcessBuilder(
                    "tar", "-xzf", tempArchive.getAbsolutePath(),
                    "-C", rootfsDir.getAbsolutePath()
            );
            pb.redirectErrorStream(true);
            Process extractProcess = pb.start();

            // Читаем вывод tar (на случай ошибок)
            BufferedReader reader = new BufferedReader(new InputStreamReader(extractProcess.getInputStream()));
            String line;
            while ((line = reader.readLine()) != null) {
                // Тихо игнорируем, чтобы не спамить в UI
            }

            int exitCode = extractProcess.waitFor();
            tempArchive.delete(); // удаляем временный архив

            if (exitCode == 0 && rootfsDir.list() != null && rootfsDir.list().length > 0) {
                logToUi("✅ Rootfs успешно распакован (" + rootfsDir.list().length + " объектов).");
            } else {
                logToUi("❌ Ошибка распаковки rootfs (код: " + exitCode + ").");
            }

        } catch (Exception e) {
            logToUi("❌ Ошибка распаковки: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Копирование бинарника qemu-aarch64 из assets и установка прав.
     */
    private void prepareQemu() {
        File qemuFile = new File(getFilesDir(), "qemu-aarch64");
        if (qemuFile.exists() && qemuFile.canExecute()) {
            logToUi("✅ QEMU уже подготовлен.");
            return;
        }

        logToUi("⚙️ Подготовка qemu-aarch64...");
        try {
            try (InputStream is = getAssets().open("qemu-aarch64");
                 FileOutputStream fos = new FileOutputStream(qemuFile)) {
                byte[] buffer = new byte[65536];
                int read;
                while ((read = is.read(buffer)) != -1) {
                    fos.write(buffer, 0, read);
                }
            }
            // Устанавливаем права на выполнение
            Runtime.getRuntime().exec(new String[]{"chmod", "700", qemuFile.getAbsolutePath()}).waitFor();
            logToUi("✅ QEMU подготовлен.");
        } catch (Exception e) {
            logToUi("❌ Ошибка подготовки QEMU: " + e.getMessage());
        }
    }

    /**
     * Диагностика перед запуском.
     */
    private void runDiagnostics() {
        File rootfsDir = new File(getFilesDir(), "debian-rootfs");
        File qemuFile = new File(getFilesDir(), "qemu-aarch64");

        if (rootfsDir.exists() && rootfsDir.list() != null && rootfsDir.list().length > 0) {
            logToUi("[OK] debian-rootfs: " + rootfsDir.list().length + " объектов");
        } else {
            logToUi("[FAIL] debian-rootfs отсутствует или пуст");
        }

        if (qemuFile.exists() && qemuFile.canExecute()) {
            logToUi("[OK] qemu-aarch64 готов");
        } else {
            logToUi("[FAIL] qemu-aarch64 отсутствует");
        }
    }

    /**
     * Запуск интерактивной оболочки Debian через QEMU user-mode.
     * Использует флаг -L для указания sysroot (libc Debian).
     * ptrace не используется, поэтому seccomp Android 16 не блокирует.
     */
    private void startInteractiveShell() {
        File rootfsDir = new File(getFilesDir(), "debian-rootfs");
        File qemuFile = new File(getFilesDir(), "qemu-aarch64");

        if (!rootfsDir.exists() || !qemuFile.exists()) {
            logToUi("❌ Невозможно запустить оболочку: файлы не готовы.");
            return;
        }

        logToUi("🚀 Запуск оболочки Debian через QEMU...");

        try {
            String[] command = {
                    qemuFile.getAbsolutePath(),
                    "-L", rootfsDir.getAbsolutePath(),
                    "-E", "HOME=/root",
                    "-E", "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                    "-E", "TERM=xterm-256color",
                    rootfsDir.getAbsolutePath() + "/bin/sh"
            };

            ProcessBuilder pb = new ProcessBuilder(command);
            pb.directory(rootfsDir);
            pb.redirectErrorStream(true);

            process = pb.start();

            // Поток чтения вывода
            startOutputReader(process.getInputStream());
            shellWriter = new PrintWriter(process.getOutputStream());

            logToUi("✅ Оболочка запущена! Введите 'ls /' для проверки.");

        } catch (Exception e) {
            logToUi("❌ Ошибка запуска оболочки: " + e.getMessage());
            e.printStackTrace();
        }
    }

    // === Вспомогательные методы ===

    private void logToUi(final String message) {
        runOnUiThread(() -> outputTextView.append(message + "\n"));
    }

    private void startOutputReader(InputStream inputStream) {
        new Thread(() -> {
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    logToUi(line);
                }
            } catch (Exception e) {
                logToUi("[поток закрыт]");
            }
        }).start();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (process != null) process.destroy();
        if (shellWriter != null) shellWriter.close();
    }
}
