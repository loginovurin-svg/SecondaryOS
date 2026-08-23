// В MainActivity.java

/**
 * Метод подготовки QEMU (вызывать вместо старого prepareProot)
 * Копирует статический бинарник из assets во внутреннюю директорию приложения
 * и делает его исполняемым.
 */
private void prepareQemu() {
    try {
        File qemuFile = new File(getFilesDir(), "qemu-aarch64");
        if (!qemuFile.exists()) {
            logToUi("Распаковка qemu-aarch64...");
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
 * Метод запуска интерактивной оболочки (заменяет команду proot)
 */
private void startInteractiveShell() {
    try {
        File rootfsDir = new File(getFilesDir(), "debian-rootfs");
        File qemuFile = new File(getFilesDir(), "qemu-aarch64");
        
        // Формируем команду запуска QEMU user-mode.
        // Мы НЕ используем ptrace, поэтому seccomp Android 16 не блокирует выполнение.
        // -L указывает на корень файловой системы гостя (где лежит libc Debian).
        // Последний аргумент - путь к исполняемому файлу внутри гостевой ФС.
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
        
        // Запускаем потоки чтения вывода и записи ввода (используйте ваши существующие методы)
        startOutputReader(process.getInputStream());
        shellWriter = new PrintWriter(process.getOutputStream());
        
        logToUi("Оболочка QEMU запущена. Введите 'ls /' для проверки.");
    } catch (Exception e) {
        logToUi("Ошибка запуска оболочки: " + e.getMessage());
    }
}

/**
 * Обновите метод runDiagnostics(), заменив проверки proot на qemu:
 */
private void runDiagnostics() {
    // ... ваш код проверки существования rootfs ...
    
    File qemuFile = new File(getFilesDir(), "qemu-aarch64");
    if (qemuFile.exists() && qemuFile.canExecute()) {
        logToUi("[OK] qemu-aarch64 найден и исполняемый.");
    } else {
        logToUi("[FAIL] qemu-aarch64 отсутствует или не имеет прав на выполнение.");
    }
}
