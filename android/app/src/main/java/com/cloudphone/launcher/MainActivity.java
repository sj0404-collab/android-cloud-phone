package com.cloudphone.launcher;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.button.MaterialButton;

public class MainActivity extends AppCompatActivity {

    public static final String PREFS = "cloud_phone";
    public static final String KEY_URL = "server_url";
    public static final String DEFAULT_URL = "http://192.168.1.100:6080/vnc.html";

    private SharedPreferences prefs;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);

        TextView subtitle = findViewById(R.id.subtitle);
        String tip = "Нужен запущенный cloud-phone (./launch.sh)\nIP: " + defaultIpHint();
        subtitle.setText(tip);

        MaterialButton launch = findViewById(R.id.launch_button);
        launch.setOnClickListener(v -> {
            String url = prefs.getString(KEY_URL, DEFAULT_URL);
            if (url.trim().isEmpty()) {
                Toast.makeText(this, "Сначала укажи адрес сервера", Toast.LENGTH_SHORT).show();
                openServerDialog();
                return;
            }
            Intent i = new Intent(this, VncActivity.class);
            i.putExtra(VncActivity.EXTRA_URL, url.trim());
            startActivity(i);
        });

        MaterialButton settings = findViewById(R.id.settings_button);
        settings.setOnClickListener(v -> openServerDialog());
    }

    private String defaultIpHint() {
        String cur = prefs.getString(KEY_URL, DEFAULT_URL);
        try {
            java.net.InetAddress addr = java.net.InetAddress.getByName(cur
                    .replace("http://", "").replace("https://", "").split(":")[0]);
            return addr != null ? cur : cur;
        } catch (Exception e) {
            return cur;
        }
    }

    private void openServerDialog() {
        View view = getLayoutInflater().inflate(R.layout.dialog_server, null);
        EditText input = view.findViewById(R.id.server_url);
        input.setText(prefs.getString(KEY_URL, DEFAULT_URL));
        input.setSelection(input.getText().length());

        new AlertDialog.Builder(this)
                .setTitle("Сервер Cloud Phone")
                .setMessage("Адрес, который печатает launch.sh после запуска.\nПример: http://192.168.1.100:6080/vnc.html")
                .setView(view)
                .setNegativeButton("Отмена", null)
                .setPositiveButton("Сохранить", (d, which) -> {
                    String url = input.getText().toString().trim();
                    prefs.edit().putString(KEY_URL, url).apply();
                    Toast.makeText(this, "Сохранено", Toast.LENGTH_SHORT).show();
                })
                .show();
    }
}