private void startInteractiveShell() throws Exception {
    File proot = prepareProot();
    File rootfs = new File(getFilesDir(), "debian");
    File tmpDir = new File(getFilesDir(), "tmp");

    List<String> cmd = new ArrayList<>();
    cmd.add(proot.getAbsolutePath());
    cmd.add("-0");                    // Эмуляция root
    cmd.add("-r"); cmd.add(rootfs.getAbsolutePath());
    cmd.add("-b"); cmd.add("/dev");
    cmd.add("-b"); cmd.add("/proc");
    cmd.add("-b"); cmd.add("/sys");
    cmd.add("-b"); cmd.add(tmpDir.getAbsolutePath() + ":/tmp");
    cmd.add("-b"); cmd.add(getFilesDir().getAbsolutePath() + ":/host");
    cmd.add("-w"); cmd.add("/root");
    cmd.add("--link2symlink");
    // УБРАЛИ -S NONE — он не работает в proot 5.3.0
    cmd.add("/bin/sh");

    ProcessBuilder pb = new ProcessBuilder(cmd);
    pb.directory(rootfs);
    pb.redirectErrorStream(true);
    pb.environment().put("HOME", "/root");
    pb.environment().put("TERM", "xterm-256color");
    pb.environment().put("PS1", "\\u@debian:\\w$ ");
    pb.environment().put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
    pb.environment().put("PROOT_TMP_DIR", tmpDir.getAbsolutePath());

    bashProcess = pb.start();
    bashIn = bashProcess.getOutputStream();
    bashOut = bashProcess.getInputStream();

    log("--- Терминал запущен ---");

    new Thread(() -> {
        byte[] buffer = new byte[2048];
        int len;
        try {
            while ((len = bashOut.read(buffer)) != -1) {
                String text = new String(buffer, 0, len, StandardCharsets.UTF_8);
                mainHandler.post(() -> logView.append(text));
            }
        } catch (Exception e) {
            mainHandler.post(() -> logView.append("\n[Разорвано]\n"));
        }
    }).start();
}

// Также обнови testLaunch():
private void testLaunch(File proot, File rootfs, File tmpDir, String tag, List<String> guestCmd) throws Exception {
    List<String> cmd = new ArrayList<>();
    cmd.add(proot.getAbsolutePath());
    cmd.add("-0");   // Только -0, без -S
    cmd.add("-r"); cmd.add(rootfs.getAbsolutePath());
    cmd.add("-b"); cmd.add("/dev");
    cmd.add("-b"); cmd.add("/proc");
    cmd.add("-b"); cmd.add("/sys");
    cmd.add("-b"); cmd.add(tmpDir.getAbsolutePath() + ":/tmp");
    cmd.addAll(guestCmd);

    ProcessBuilder pb = new ProcessBuilder(cmd);
    pb.directory(rootfs);
    pb.redirectErrorStream(true);
    pb.environment().put("HOME", "/root");
    pb.environment().put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
    pb.environment().put("PROOT_TMP_DIR", tmpDir.getAbsolutePath());

    Process p = pb.start();
    try (BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
        String line;
        while ((line = br.readLine()) != null) {
            log("[" + tag + "] " + line);
        }
    }
    int code = p.waitFor();
    if (code != 0) throw new Exception("Тест " + tag + " код: " + code);
}
