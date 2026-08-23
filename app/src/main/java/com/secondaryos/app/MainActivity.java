package com.secondaryos.app;

import android.app.Activity;
import android.os.Bundle;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Button;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.BufferedReader;
import java.io.InputStreamReader;

public class MainActivity extends Activity {

    private TextView outputTextView;
    private EditText inputEditText;
    private Button sendButton;
    
    private Process process;
    private PrintWriter shellWriter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // Простая разметка для теста (в Фазе 4 будет полноценный UI)
        outputTextView = new TextView(this);
        outputTextView.setId(android.R.id.text1);
        outputTextView.setText("Инициализация SecondaryOS...\n");
        
        inputEditText = new EditText(this);
        inputEditText.setId(android.R.id.input);
        inputEditText.setHint("Введите команду (например, ls /)");
        
        sendButton = new Button(this);
        sendButton.setText("Выполнить");
        
        // Простая вертикальная компоновка (в реальном проекте используйте XML)
        android.widget.LinearLayout layout = new android.widget.LinearLayout(this);
        layout.setOrientation(android.widget.LinearLayout.VERTICAL);
        layout.addView(outputTextView, new android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT, 0, 1.0f));
        layout.addView(inputEditText, new android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT, 
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT));
        layout.addView(sendButton, new android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT, 
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT));
        
        setContentView(layout);

        // Запускаем подготовку и диагностику
        prepareQemu();
        runDiagnostics();
        
        // Обработчик кнопки
        sendButton.setOnClickListener(v -> {
            String cmd = inputEditText.getText().toString();
            if (shellWriter != null) {
                shellWriter.println(cmd);
                shellWriter.flush();
                inputEditText.setText("");
            } else {
                logToUi("Оболочка еще не запущена!");
            }
        });

        // Запускаем оболочку после небольшой задержки, чтобы UI отрисовался
        new Thread(() -> {
            try { Thread.sleep(1000); } catch (InterruptedException e) {}
            startInteractiveShell();
        }).start();
    }

    /**
     * Метод подготовки QEMU. Копирует статический бинарник из assets 
     * во внутреннюю директорию приложения и делает его исполняемым.
     */
    private void prepareQemu() {
        try {
            File qemuFile = new File(getFilesDir(), "qemu-aarch64");
            if (!qemuFile.exists()) {
                logToUi("Распаковка qemu-aarch64 из assets...");
                InputStream is = getAssets().open("qemu-aarch64");
                FileOutputStream fos = new FileOutputStream(qemuFile);
                byte[] buffer = new byte[8192];
                int length;
                while ((length = is.read(buffer)) > 0) {
                    fos.write(buffer, 0, length);
                }
                fos.close();
                is.close();
                
                // Делаем файл исполняемым (chmod 700)
                Runtime.getRuntime().exec("chmod 700 " + qemuFile.getAbsolutePath()).waitFor();
                logToUi("QEMU успешно подготовлен.");
            }
        } catch (Exception e) {
            logToUi("Критическая ошибка подготовки QEMU: " + e.getMessage());
        }
    }

    /**
     * Метод запуска интерактивной оболочки через QEMU user-mode.
     * Заменяет старый вызов proot.
     */
    private void startInteractiveShell() {
        try {
            File rootfsDir = new File(getFilesDir(), "debian-rootfs");
            File qemuFile = new File(getFilesDir(), "qemu-aarch64");
            
            if (!rootfsDir.exists()) {
                logToUi("ОШИБКА: Директория debian-rootfs не найдена!");
                return;
            }
            if (!qemuFile.exists()) {
                logToUi("ОШИБКА: Бинарник qemu-aarch64 не найден!");
                return;
            }

            logToUi("Запуск QEMU user-mode...");
            
            // Формируем команду запуска. 
            // -L указывает на sysroot (где лежит libc Debian).
            // Мы НЕ используем ptrace, поэтому seccomp Android 16 не блокирует выполнение.
            String[] command = {
                qemuFile.getAbsolutePath(),
                "-L", rootfsDir.getAbsolutePath(),
                "-E", "HOME=/root",
                "-E", "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "-E", "TERM=xterm-256color",
                rootfsDir.getAbsolutePath() + "/bin/sh"
            };
            
            ProcessBuilder processBuilder = new ProcessBuilder(command);
            processBuilder.directory(rootfsDir);
            // Перенаправляем stderr в stdout, чтобы перехватывать все сообщения об ошибках
            processBuilder.redirectErrorStream(true);
            
            process = processBuilder.start();
            
            // Запускаем поток чтения вывода
            startOutputReader(process.getInputStream());
            shellWriter = new PrintWriter(process.getOutputStream());
            
            logToUi("✅ Оболочка QEMU запущена. Введите 'ls /' для проверки.");
        } catch (Exception e) {
            logToUi("Ошибка запуска оболочки: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Диагностика состояния перед запуском.
     */
    private void runDiagnostics() {
        File rootfsDir = new File(getFilesDir(), "debian-rootfs");
        if (rootfsDir.exists()) {
            logToUi("[OK] debian-rootfs найден.");
        } else {
            logToUi("[FAIL] debian-rootfs отсутствует.");
        }

        File qemuFile = new File(getFilesDir(), "qemu-aarch64");
        if (qemuFile.exists() && qemuFile.canExecute()) {
            logToUi("[OK] qemu-aarch64 найден и исполняемый.");
        } else {
            logToUi("[FAIL] qemu-aarch64 отсутствует или не имеет прав на выполнение.");
        }
    }

    // --- Вспомогательные методы ---

    private void logToUi(final String message) {
        runOnUiThread(() -> {
            outputTextView.append(message + "\n");
        });
    }

    private void startOutputReader(final InputStream inputStream) {
        new Thread(() -> {
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    logToUi(line);
                }
            } catch (Exception e) {
                logToUi("Ошибка чтения потока: " + e.getMessage());
            }
        }).start();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (process != null) {
            process.destroy();
        }
        if (shellWriter != null) {
            shellWriter.close();
        }
    }
}
