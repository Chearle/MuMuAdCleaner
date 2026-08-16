package dev.adclean.mumu;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.Button;
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
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView rootStatus;
    private TextView logView;
    private Button btnApply;
    private Button btnRestore;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        rootStatus = findViewById(R.id.rootStatus);
        logView = findViewById(R.id.logView);
        btnApply = findViewById(R.id.btnApply);
        btnRestore = findViewById(R.id.btnRestore);

        btnApply.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                runScript("apply.sh", "正在去除广告…");
            }
        });
        btnRestore.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                runScript("restore.sh", "正在恢复广告…");
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
                            rootStatus.setText("Root 可用，可以去除广告");
                            rootStatus.setTextColor(Color.parseColor("#FF6DFFB3"));
                            appendLog("Root 检测成功\n" + r.output.trim());
                        } else {
                            rootStatus.setText("没有 Root。请打开 KernelSU，授权本应用后再点「去除广告」");
                            rootStatus.setTextColor(Color.parseColor("#FFFFD37A"));
                            appendLog("Root 检测失败。\n" + r.output);
                        }
                    }
                });
            }
        });
    }

    private void runScript(final String assetName, final String pending) {
        setBusy(true);
        appendLog(pending);
        io.execute(new Runnable() {
            @Override
            public void run() {
                Result r;
                try {
                    File script = copyAssetUnix(assetName);
                    String remote = "/data/local/tmp/mumu-adclean-" + assetName;
                    String cmd = "cat '" + script.getAbsolutePath() + "' | tr -d '\\r' > " + remote
                            + " && chmod 755 " + remote
                            + " && sh " + remote
                            + " ; echo EXIT:$?";
                    r = su(cmd);
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
                            rootStatus.setText("完成。请看桌面，搜索栏和「每日新发现」应已消失");
                            rootStatus.setTextColor(Color.parseColor("#FF6DFFB3"));
                        } else {
                            rootStatus.setText("执行失败，请把下方日志发我");
                            rootStatus.setTextColor(Color.parseColor("#FFFFB4C4"));
                        }
                    }
                });
            }
        });
    }

    private File copyAssetUnix(String name) throws Exception {
        InputStream in = getAssets().open(name);
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try {
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) {
                for (int i = 0; i < n; i++) {
                    if (buf[i] != '\r') {
                        bos.write(buf[i]);
                    }
                }
            }
        } finally {
            in.close();
        }
        File out = new File(getCacheDir(), name);
        FileOutputStream fos = new FileOutputStream(out);
        try {
            bos.writeTo(fos);
        } finally {
            fos.close();
        }
        out.setReadable(true, false);
        return out;
    }

    private static Result su(String script) {
        String[][] cmds = new String[][] {
                new String[] {"su", "-c", "sh"},
                new String[] {"su"},
                new String[] {"/system/bin/su", "-c", "sh"},
                new String[] {"/debug_ramdisk/su", "-c", "sh"}
        };
        Result last = Result.fail("su not found");
        for (int i = 0; i < cmds.length; i++) {
            last = suOnce(cmds[i], script);
            if (last.ok || last.output.contains("uid=0") || last.output.contains("DONE")) {
                return last;
            }
        }
        return last;
    }

    private static Result suOnce(String[] cmd, String script) {
        Process p = null;
        try {
            p = Runtime.getRuntime().exec(cmd);
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
            if (code == 0) {
                return Result.ok(merged);
            }
            return Result.fail("cmd=" + cmd[0] + " exit=" + code + "\n" + merged);
        } catch (Exception e) {
            return Result.fail("cmd=" + cmd[0] + " " + e.toString());
        } finally {
            if (p != null) {
                p.destroy();
            }
        }
    }

    private void appendLog(String text) {
        if (text == null || text.trim().length() == 0) {
            return;
        }
        String old = logView.getText() == null ? "" : logView.getText().toString();
        logView.setText((old + "\n\n" + text.trim()).trim());
    }

    private void setBusy(boolean busy) {
        btnApply.setEnabled(!busy);
        btnRestore.setEnabled(!busy);
        btnApply.setAlpha(busy ? 0.5f : 1f);
        btnRestore.setAlpha(busy ? 0.5f : 1f);
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
