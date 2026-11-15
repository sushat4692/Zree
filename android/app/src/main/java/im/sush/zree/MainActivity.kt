package im.sush.zree

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { ZreeApp() }
    }
}

@Composable
fun ZreeApp() {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            // Placeholder: the real screen lands once libzree_core.so builds.
            Text("Zree")
        }
    }
}
