package com.herasat.vpn

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Background = Color(0xFF0B1020)
private val Surface = Color(0xFF151D31)
private val Accent = Color(0xFF55D6BE)
private val Muted = Color(0xFF9AA8BD)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            var language by remember { mutableStateOf("fa") }
            MaterialTheme(colorScheme = darkColorScheme(
                background = Background, surface = Surface, primary = Accent,
                onBackground = Color.White, onSurface = Color.White
            )) {
                Surface(Modifier.fillMaxSize(), color = Background) {
                    Column(Modifier.fillMaxSize().padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically) {
                            Text("HERASAT", fontSize = 23.sp, fontWeight = FontWeight.Black, color = Accent)
                            TextButton(onClick = { language = if (language == "fa") "en" else "fa" }) {
                                Text(if (language == "fa") "EN" else "فا")
                            }
                        }
                        Spacer(Modifier.height(38.dp))
                        Text(if (language == "fa") "اتصال امن، با انتخاب شما" else "Secure connection, your choice",
                            color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(28.dp))
                        Box(Modifier.size(190.dp).background(Surface, RoundedCornerShape(100.dp)),
                            contentAlignment = Alignment.Center) {
                            Text("OFF", color = Accent, fontSize = 38.sp, fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.height(24.dp))
                        Text(if (language == "fa") "وضعیت: نسخه اولیه" else "Status: prototype",
                            color = Muted)
                        Spacer(Modifier.height(32.dp))
                        Button(onClick = {
                            Toast.makeText(this@MainActivity,
                                if (language == "fa") "هسته اتصال Xray هنوز به پروژه اضافه نشده است." else "The Xray tunnel core has not been integrated yet.",
                                Toast.LENGTH_LONG).show()
                        }, modifier = Modifier.fillMaxWidth().height(54.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Accent),
                            shape = RoundedCornerShape(16.dp)) {
                            Text(if (language == "fa") "اتصال" else "Connect",
                                color = Background, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                        }
                        Spacer(Modifier.height(12.dp))
                        OutlinedButton(onClick = {
                            Toast.makeText(this@MainActivity,
                                if (language == "fa") "هنوز سروری دریافت نشده است." else "No servers have been loaded yet.",
                                Toast.LENGTH_SHORT).show()
                        }, modifier = Modifier.fillMaxWidth().height(52.dp),
                            shape = RoundedCornerShape(16.dp)) {
                            Text(if (language == "fa") "دریافت سرورها (به‌زودی)" else "Fetch servers (coming soon)")
                        }
                        Spacer(Modifier.weight(1f))
                        Text("VLESS • VMess • Trojan • Shadowsocks", color = Muted, fontSize = 12.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("Herasat 0.1.0 • Prototype", color = Muted, fontSize = 11.sp)
                    }
                }
            }
        }
    }
}
