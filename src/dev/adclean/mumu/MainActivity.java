package dev.adclean.mumu;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final String[] SU = {"su", "-c", "sh"};
    private static final String[] ASSETS = {
            "common.sh", "apply.sh", "persist.sh", "restore.sh"
    };
    private static final int LOG_MAX = 4000;

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());

    private TextView rootStatus;
    private TextView logView;
    private Button btnApply;
    private Button btnRestore;
    private CheckBox transientMode;
    private int colorOk;
    private int colorWarn;
    private int colorFail;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        rootStatus = findViewById(R.id.rootStatus);
        logView = findViewById(R.id.logView);
        btnApply = findViewById(R.id.btnApply);
        btnRestore = findViewById(R.id.btnRestore);
        transientMode = findViewById(R.id.transientMode);
        colorOk = getColor(R.color.ok);
        colorWarn = getColor(R.color.warn);
        colorFail = getColor(R.color.danger_text);

        btnApply.setOnClickListener(new android.view.View.OnClickListener() {
            @Override
            public void onClick(android.view.View v) {
                String args = transientMode.isChecked() ? " --transient" : "";
                runScript("apply.sh", R.string.applying, args);
            }
        });
        btnRestore.setOnClickListener(new android.view.View.OnClickListener() {
            @Override
            public void onClick(android.view.View v) {
                runScript("restore.sh", R.string.restoring, "");
            }
        });
        checkRoot();
    }

    private void checkRoot() {
        setBusy(true);
        io.execute(new Runnable() {
            @Override
            public void run() {
                final Result r = su("id");
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        setBusy(false);
                        if (r.ok && r.output.contains("uid=0")) {
                            setStatus(getString(R.string.root_ok), colorOk);
                            appendLog(getString(R.string.root_ok_log) + "\n" + r.output.trim());
                        } else {
                            setStatus(getString(R.string.root_fail), colorWarn);
                            appendLog(getString(R.string.root_fail_log) + "\n" + r.output);
                        }
                    }
                });
            }
        });
    }

    private void runScript(final String name, final int pendingId, final String args) {
        setBusy(true);
        appendLog(getString(pendingId));
        io.execute(new Runnable() {
            @Override
            public void run() {
                Result r;
                try {
                    stageAssets();
                    r = su("chmod 755 /data/local/tmp/mumu-adclean-*.sh && sh /data/local/tmp/mumu-adclean-"
                            + name + args);
                    if (r.output.contains("DONE")) {
                        r = Result.ok(r.output);
                    }
                } catch (Exception e) {
                    r = Result.fail(e.toString());
                }
                final Result out = r;
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        setBusy(false);
                        appendLog(out.output);
                        if (out.ok && out.output.contains("DONE")) {
                            setStatus(getString(R.string.apply_ok), colorOk);
                        } else {
                            setStatus(getString(R.string.apply_fail), colorFail);
                        }
                    }
                });
            }
        });
    }

    private void stageAssets() throws Exception {
        File dir = getCacheDir();
        StringBuilder cmd = new StringBuilder();
        for (int i = 0; i < ASSETS.length; i++) {
            String name = ASSETS[i];
            File out = new File(dir, name);
            writeUnix(out, loadAsset(name));
            cmd.append("cat '").append(out.getAbsolutePath()).append("'")
                    .append(" > /data/local/tmp/mumu-adclean-").append(name)
                    .append(" && ");
        }
        Result r = su(cmd.append("true").toString());
        if (!r.ok) {
            throw new IllegalStateException(r.output);
        }
    }

    private String loadAsset(String name) throws Exception {
        InputStream in = getAssets().open(name);
        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            return new String(bos.toByteArray(), StandardCharsets.UTF_8).replace("\r", "");
        } finally {
            in.close();
        }
    }

    private static void writeUnix(File out, String text) throws Exception {
        FileOutputStream fos = new FileOutputStream(out);
        try {
            fos.write(text.getBytes(StandardCharsets.UTF_8));
        } finally {
            fos.close();
        }
        out.setReadable(true, false);
    }

    private static Result su(String script) {
        Process p = null;
        try {
            p = Runtime.getRuntime().exec(SU);
            StreamCollector stdout = new StreamCollector(p.getInputStream());
            StreamCollector stderr = new StreamCollector(p.getErrorStream());
            stdout.start();
            stderr.start();
            OutputStream os = p.getOutputStream();
            os.write((script + "\nexit\n").getBytes(StandardCharsets.UTF_8));
            os.flush();
            os.close();
            int code = p.waitFor();
            stdout.join();
            stderr.join();
            String merged = (stdout.text + "\n" + stderr.text).trim();
            return code == 0 ? Result.ok(merged) : Result.fail("exit=" + code + "\n" + merged);
        } catch (Exception e) {
            return Result.fail(e.toString());
        } finally {
            if (p != null) {
                p.destroy();
            }
        }
    }

    private void setStatus(String text, int color) {
        rootStatus.setText(text);
        rootStatus.setTextColor(color);
    }

    private void appendLog(String text) {
        if (text == null) {
            return;
        }
        String add = text.trim();
        if (add.length() == 0) {
            return;
        }
        String old = logView.getText() == null ? "" : logView.getText().toString();
        String next = (old + "\n\n" + add).trim();
        if (next.length() > LOG_MAX) {
            next = next.substring(next.length() - LOG_MAX);
        }
        logView.setText(next);
    }

    private void setBusy(boolean busy) {
        btnApply.setEnabled(!busy);
        btnRestore.setEnabled(!busy);
        transientMode.setEnabled(!busy);
        btnApply.setAlpha(busy ? 0.5f : 1f);
        btnRestore.setAlpha(busy ? 0.5f : 1f);
        transientMode.setAlpha(busy ? 0.5f : 1f);
    }

    static class StreamCollector extends Thread {
        private final InputStream in;
        String text = "";

        StreamCollector(InputStream in) {
            this.in = in;
        }

        @Override
        public void run() {
            try {
                ByteArrayOutputStream bos = new ByteArrayOutputStream();
                byte[] buf = new byte[1024];
                int n;
                while ((n = in.read(buf)) > 0) {
                    bos.write(buf, 0, n);
                }
                text = new String(bos.toByteArray(), StandardCharsets.UTF_8);
            } catch (Exception ignored) {
            }
        }
    }

    static class Result {
        final boolean ok;
        final String output;

        Result(boolean ok, String output) {
            this.ok = ok;
            this.output = output == null ? "" : output;
        }

        static Result ok(String output) {
            return new Result(true, output);
        }

        static Result fail(String output) {
            return new Result(false, output);
        }
    }
}
