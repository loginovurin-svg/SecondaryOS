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

/**
 * SecondaryOS — MainActivity
 * Фаза 1: Запуск Debian 11 (arm64) через QEMU user-mode на Android 16.
 *
 * Архитектура:
 * - proot НЕ используется (seccomp Android 16 блокирует ptrace → SIGSYS).
 * - QEMU user-mode транслирует syscall'ы гостя (glibc Debian) в syscall'ы хоста
 *   (Bionic Android) БЕЗ ptrace → seccomp не срабатывает.
 * - Флаг -L указывает sysroot (где лежит libc и библиотеки Debian).
 * - Графика: пока консоль. В Фазе 2 подключим Wayland (Android = compositor).
 */
public class MainActivity extends Activity {

    // UI-элементы
    private TextView outputTextView;
    private EditText inputEditText;
    private Button sendButton;

    // Процесс и потоки оболочки
    private Process shellProcess;
    private PrintWriter shellWriter;
    private Thread outputReaderThread;

    // Пути внутри приватной директории приложения
    // getFilesDir() → /data/user/0/com.secondaryos.app/files/
    // getCacheDir() → /data/user/0/com.secondaryos.app/cache/
    private File rootfsDir;
    private File qemuBinary;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // === Инициализация путей ===
        rootfsDir = new File(getFilesDir(), "debian-rootfs");
        qemuBinary = new File(getFilesDir(), "qemu-aarch64");

        // === Простой UI: тёмный терминал ===
        outputTextView = new TextView(this);
        outputTextView.setText("SecondaryOS — инициализация...\n");
        outputTextView.setTextColor(0xFF00FF41);      // зелёный терминальный
        outputTextView.setBackgroundColor(0xFF0A0A0A); // почти чёрный фон
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

        // Вертикальная компоновка
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

        // === Обработчик кнопки отправки команды ===
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

        // === Запуск bootstrap в фоновом потоке (не блокируем UI) ===
        new Thread(this::bootstrap).start();
    }

    /**
     * Главная последовательность запуска (выполняется в фоне):
     * 1. Распаковать rootfs из assets
     * 2. Подготовить qemu-aarch64 из assets
     * 3. Диагностика
     * 4. Запуск оболочки
     */
    private void bootstrap() {
        extractRootfs();
        prepareQemu();
        runDiagnostics();

        // Небольшая пауза, чтобы пользователь успел прочитать диагностику
        try { Thread.sleep(500); } catch (InterruptedException ignored) {}

        startInteractiveShell();
    }

    /**
     * Распаковка debian-rootfs.tar.xz из assets во внутреннюю память.
     *
     * Почему tar.xz, а не tar.gz:
     * - Официальные образы Debian cloud идут в .tar.xz (меньше размер APK).
     * - Android 11+ (toybox) поддерживает xz из коробки.
     *
     * Схема: копируем архив в cache → xz -d -c | tar -xf - -C rootfsDir
     */
    private void extractRootfs() {
        // Если уже распакован и не пуст — пропускаем (экономим время при повторных запусках)
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
            // 1. Копируем архив из assets во временный файл в cache
            File tempArchive = new File(getCacheDir(), "debian-rootfs.tar.xz");
            try (InputStream is = getAssets().open("debian-rootfs.tar.xz");
                 FileOutputStream fos = new FileOutputStream(tempArchive)) {
                byte[] buffer = new byte[65536];
                int read;
                while ((read = is.read(buffer)) != -1) {
                    fos.write(buffer, 0, read);
                }
            }
            logToUi("  архив скопирован в cache, запускаем распаковку...");

            // 2. Распаковываем: xz разжимает поток, tar извлекает файлы
            //    toybox в Android 11+ поддерживает обе утилиты.
            ProcessBuilder pb = new ProcessBuilder(
                    "sh", "-c",
                    "xz -d -c '" + tempArchive.getAbsolutePath() + "' | tar -xf - -C '" + rootfsDir.getAbsolutePath() + "'"
            );
            pb.redirectErrorStream(true);
            Process extractProcess = pb.start();

            // Читаем вывод (ошибки tar/xz попадут сюда)
            BufferedReader reader = new BufferedReader(new InputStreamReader(extractProcess.getInputStream()));
            String line;
            while ((line = reader.readLine()) != null) {
                // Игнорируем штатный вывод tar, но если будет ошибка — она тоже здесь
            }

            int exitCode = extractProcess.waitFor();
            tempArchive.delete(); // удаляем временный архив, экономим место

            if (exitCode == 0 && rootfsDir.list() != null && rootfsDir.list().length > 0) {
                logToUi("✅ rootfs распакован (" + rootfsDir.list().length + " объектов).");
            } else {
                logToUi("❌ ошибка распаковки rootfs (код: " + exitCode + ").");
                logToUi("  проверьте, что в assets лежит валидный debian-rootfs.tar.xz");
            }

        } catch (Exception e) {
            logToUi("❌ ошибка распаковки: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Копирование бинарника qemu-aarch64 из assets и установка прав на выполнение.
     *
     * Важно: бинарник ДОЛЖЕН быть скомпилирован под aarch64 (хост = устройство).
     * Если в assets лежит x86_64-версия — получишь "Exec format error".
     * Проверка архитектуры делается в prepare_assets.sh на этапе сборки.
     */
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
            // chmod 700 — только владелец (приложение) может читать/запускать
            Runtime.getRuntime().exec(new String[]{"chmod", "700", qemuBinary.getAbsolutePath()}).waitFor();
            logToUi("✅ qemu-aarch64 готов.");
        } catch (Exception e) {
            logToUi(" ошибка подготовки QEMU: " + e.getMessage());
        }
    }

    /**
     * Быстрая диагностика перед запуском.
     */
    private void runDiagnostics() {
        if (rootfsDir.exists() && rootfsDir.list() != null && rootfsDir.list().length > 0) {
            logToUi("[OK] debian-rootfs: " + rootfsDir.list().length + " объектов");
        } else {
            logToUi("[FAIL] debian-rootfs отсутствует или пуст — оболочка не запустится.");
        }

        if (qemuBinary.exists() && qemuBinary.canExecute()) {
            logToUi("[OK] qemu-aarch64 готов к запуску.");
        } else {
            logToUi("[FAIL] qemu-aarch64 отсутствует — скачайте его в prepare_assets.sh.");
        }
    }

    /**
     * Запуск интерактивной оболочки Debian через QEMU user-mode.
     *
     * Ключевые флаги:
     *   -L <rootfs>  — sysroot гостя (где лежит /lib, /usr/lib, libc.so.6 от Debian).
     *                  Без этого QEMU не найдёт glibc и упадёт.
     *   -E VAR=val   — переменные окружения гостя (PATH, HOME, TERM).
     *
     * Почему это работает на Android 16:
     *   QEMU user-mode НЕ использует ptrace. Он транслирует syscall'ы на уровне
     *   библиотеки (syscall-emulation), поэтому seccomp-bpf хоста их не блокирует.
     *   Proot же делал ptrace(PTRACE_SYSCALL) → seccomp убивал процесс с SIGSYS.
     */
    private void startInteractiveShell() {
        if (!rootfsDir.exists() || !qemuBinary.exists()) {
            logToUi("❌ невозможно запустить оболочку: файлы не готовы.");
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
            pb.directory(rootfsDir);          // рабочая директория процесса
            pb.redirectErrorStream(true);     // stderr → stdout (ловим всё)

            shellProcess = pb.start();

            // Поток чтения вывода (чтобы UI не завис)
            outputReaderThread = new Thread(this::readShellOutput);
            outputReaderThread.setDaemon(true);
            outputReaderThread.start();

            // Поток записи команд (stdin оболочки)
            shellWriter = new PrintWriter(shellProcess.getOutputStream(), true);

            logToUi("✅ оболочка запущена. введите 'ls /' для проверки.");

        } catch (Exception e) {
            logToUi("❌ ошибка запуска оболочки: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Чтение вывода оболочки в фоновом потоке.
     * Работает пока процесс жив. При завершении — выходим из цикла.
     */
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

    // === Утилиты ===

    /**
     * Безопасный вывод в UI из любого потока.
     */
    private void logToUi(final String message) {
        runOnUiThread(() -> outputTextView.append(message + "\n"));
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        // Корректное завершение: убиваем процесс и закрываем потоки
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
