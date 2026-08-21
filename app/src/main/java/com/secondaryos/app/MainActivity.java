package com.secondaryos.app;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.system.Os;
import android.util.Log;
import android.view.Gravity;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream;

import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    private static final String TAG = "SecondaryOS";
    private static final int INSTALL_VERSION = 2;

    private TextView logView;
    private Button startButton;
    private EditText commandInput;
    private Button sendButton;
    
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    
    // Переменные для интерактивного терминала
    private Process bashProcess;
    private OutputStream bashIn;
    private InputStream bashOut;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(16, 16, 16, 16);

        startButton = new Button(this);
        startButton.setText("ПОДГОТОВИТЬ И ЗАПУСТИТЬ ТЕРМИНАЛ");
        root.addView(startButton);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        logView = new TextView(this);
        logView.setTypeface(Typeface.MONOSPACE);
        logView.setTextSize(12f);
        logView.setText("Ожидание запуска...\n");
        scroll.addView(logView);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1.0f));

        LinearLayout inputPanel = new LinearLayout(this);
        inputPanel.setOrientation(LinearLayout.HORIZONTAL);
        inputPanel.setGravity(Gravity.CENTER_VERTICAL);

        commandInput = new EditText(this);
        commandInput.setHint("Введите команду (например, ls)");
        commandInput.setTypeface(Typeface.MONOSPACE);
        commandInput.setTextSize(14f);
        commandInput.setSingleLine(true);
        commandInput.setImeOptions(EditorInfo.IME_ACTION_SEND);
        commandInput.setEnabled(false); 
        
        commandInput.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                sendCommand();
                return true;
            }
            return false;
        });

        sendButton = new Button(this);
        sendButton.setText("➔");
        sendButton.setEnabled(false);
        sendButton.setOnClickListener(v -> sendCommand());

        inputPanel.addView(commandInput, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0f));
        inputPanel.addView(sendButton, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.MATCH_PARENT));
        root.addView(inputPanel, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        setContentView(root);
        startButton.setOnClickListener(v -> startLinux());
    }

    private void log(String msg) {
        Log.i(TAG, msg);
        mainHandler.post(() -> logView.append(msg + "\n"));
    }

    private void startLinux() {
        startButton.setEnabled(false);
        log("=== Инициализация окружения ===");
        executor.execute(() -> {
            try {
                runDiagnostics();
                startInteractiveShell();
            } catch (Throwable t) {
                log("✗ КРИТИЧЕСКАЯ ОШИБКА: " + t.getMessage());
                Log.e(TAG, "fatal", t);
            } finally {
                mainHandler.post(() -> {
                    startButton.setText("ПЕРЕЗАПУСТИТЬ");
                    startButton.setEnabled(true);
                    commandInput.setEnabled(true);
                    sendButton.setEnabled(true);
                    commandInput.requestFocus();
                });
            }
        });
    }

    private void runDiagnostics() throws Exception {
        File proot = prepareProot();
        log("proot: exists=" + proot.exists() + " exec=" + proot.canExecute());

        File rootfs = new File(getFilesDir(), "debian");
        File marker = new File(getFilesDir(), ".secondaryos_installed");
        String markerText = marker.exists() ? readFile(marker) : "";

        if (!markerText.equals(String.valueOf(INSTALL_VERSION)) || !rootfs.exists()) {
            log("Распаковываю rootfs (это может занять время)...");
            if (rootfs.exists()) deleteRecursively(rootfs);
            extractRootfs(rootfs);
            writeFile(marker, String.valueOf(INSTALL_VERSION));
        } else {
            log("Rootfs уже распакован.");
        }

        rewriteNsswitch(rootfs);

        File tmpDir = new File(getFilesDir(), "tmp");
        tmpDir.mkdirs();

        // Тест A: uname
        List<String> a = new ArrayList<>();
        a.add("/usr/bin/uname"); a.add("-a");
        testLaunch(proot, rootfs, tmpDir, "A", a);

        // Тест C: sh -c echo
        List<String> c = new ArrayList<>();
        c.add("/bin/sh"); c.add("-c"); c.add("echo BASH_OK");
        testLaunch(proot, rootfs, tmpDir, "C", c);

        // Тест D: ls через sh (проверка, что ls вообще работает)
        List<String> d = new ArrayList<>();
        d.add("/bin/sh"); d.add("-c"); d.add("/bin/ls /");
        testLaunch(proot, rootfs, tmpDir, "D", d);

        log("=== Диагностика пройдена успешно ===");
    }

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

        log("--- Терминал запущен. Введите команду. ---");

        new Thread(() -> {
            byte[] buffer = new byte[2048];
            int len;
            try {
                while ((len = bashOut.read(buffer)) != -1) {
                    String text = new String(buffer, 0, len, StandardCharsets.UTF_8);
                    mainHandler.post(() -> logView.append(text));
                }
            } catch (Exception e) {
                mainHandler.post(() -> logView.append("\n[Соединение разорвано]\n"));
            }
        }).start();
    }

    private void sendCommand() {
        String cmd = commandInput.getText().toString();
        if (cmd.isEmpty()) return;
        
        logView.append("\n$ " + cmd + "\n");
        commandInput.setText("");

        if (bashIn != null) {
            try {
                bashIn.write((cmd + "\n").getBytes(StandardCharsets.UTF_8));
                bashIn.flush();
            } catch (Exception e) {
                log("Ошибка отправки: " + e.getMessage());
            }
        }
    }

    private void rewriteNsswitch(File rootfs) {
        File nss = new File(rootfs, "etc/nsswitch.conf");
        writeFile(nss,
                "passwd: files\n" +
                "group: files\n" +
                "shadow: files\n" +
                "hosts: files dns\n" +
                "networks: files\n" +
                "protocols: files\n" +
                "services: files\n" +
                "ethers: files\n" +
                "rpc: files\n");
    }

    private void testLaunch(File proot, File rootfs, File tmpDir, String tag, List<String> guestCmd) throws Exception {
        List<String> cmd = new ArrayList<>();
        cmd.add(proot.getAbsolutePath());
        cmd.add("-0");
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
        if (code != 0) {
            throw new Exception("Тест " + tag + " завершился с кодом " + code);
        }
    }

    private File prepareProot() throws Exception {
        File libProot = new File(getApplicationInfo().nativeLibraryDir, "libproot.so");
        if (libProot.exists() && libProot.canExecute()) {
            return libProot;
        }
        File proot = new File(getFilesDir(), "proot");
        if (!proot.exists() || proot.length() == 0) {
            try (InputStream in = getAssets().open("proot_static");
                 FileOutputStream out = new FileOutputStream(proot)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
        }
        Os.chmod(proot.getAbsolutePath(), 0b111101101);
        return proot;
    }

    private void extractRootfs(File rootfs) throws Exception {
        rootfs.mkdirs();
        String destCanonical = rootfs.getCanonicalPath();
        int count = 0;

        try (InputStream raw = getAssets().open("debian-rootfs.tar.xz");
             XZCompressorInputStream xz = new XZCompressorInputStream(new BufferedInputStream(raw, 1 << 20));
             TarArchiveInputStream tar = new TarArchiveInputStream(xz)) {

            TarArchiveEntry entry;
            while ((entry = (TarArchiveEntry) tar.getNextEntry()) != null) {
                String name = entry.getName();
                while (name.startsWith("./")) name = name.substring(2);
                while (name.startsWith("/")) name = name.substring(1);
                if (name.isEmpty()) continue;

                File out = new File(rootfs, name);
                if (!out.getCanonicalPath().startsWith(destCanonical)) continue;

                if (entry.isDirectory()) {
                    out.mkdirs();
                    safeChmod(out, entry.getMode() & 07777, true);
                } else if (entry.isSymbolicLink()) {
                    out.getParentFile().mkdirs();
                    if (out.exists()) out.delete();
                    try { Os.symlink(entry.getLinkName(), out.getAbsolutePath()); } 
                    catch (Throwable t) { log("symlink ошибка: " + name); }
                } else if (entry.isLink()) {
                    out.getParentFile().mkdirs();
                    String target = entry.getLinkName();
                    while (target.startsWith("./")) target = target.substring(2);
                    while (target.startsWith("/")) target = target.substring(1);
                    File targetFile = new File(rootfs, target);
                    if (targetFile.exists()) {
                        try { Os.link(targetFile.getAbsolutePath(), out.getAbsolutePath()); } 
                        catch (Throwable t) { copyFile(targetFile, out); safeChmod(out, entry.getMode() & 07777, false); }
                    }
                } else {
                    out.getParentFile().mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(out)) {
                        byte[] buf = new byte[65536];
                        int n;
                        while ((n = tar.read(buf)) > 0) fos.write(buf, 0, n);
                    }
                    safeChmod(out, entry.getMode() & 07777, false);
                }
                count++;
                if (count % 2000 == 0) log("Распаковано записей: " + count);
            }
        }
        log("Всего записей в rootfs: " + count);
    }

    private void copyFile(File src, File dst) throws Exception {
        try (java.io.FileInputStream in = new java.io.FileInputStream(src);
             FileOutputStream out = new FileOutputStream(dst)) {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
    }

    private void safeChmod(File f, int mode, boolean isDir) {
        try {
            int m = (mode != 0) ? mode : (isDir ? 0755 : 0644);
            Os.chmod(f.getAbsolutePath(), m);
        } catch (Throwable t) {
            f.setReadable(true, false);
            f.setWritable(true, false);
            f.setExecutable(true, false);
        }
    }

    private void deleteRecursively(File f) {
        File[] list = f.listFiles();
        if (list != null) for (File c : list) deleteRecursively(c);
        f.delete();
    }

    private String readFile(File f) {
        try { return new String(Files.readAllBytes(f.toPath())).trim(); } 
        catch (Throwable t) { return ""; }
    }

    private void writeFile(File f, String text) {
        try (FileOutputStream fos = new FileOutputStream(f)) {
            fos.write(text.getBytes());
        } catch (Throwable t) {
            log("Не удалось записать файл: " + t.getMessage());
        }
    }
    
    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (bashProcess != null) {
            bashProcess.destroy();
        }
    }
}
