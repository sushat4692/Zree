package im.sush.zree

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle

class MainActivity : ComponentActivity() {
    private val vm: ZreeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { ZreeRoot(vm) }
    }

    override fun onStop() {
        super.onStop()
        // best-effort flush when the app leaves the foreground
        vm.onAppBackground()
    }
}

@Composable
fun ZreeRoot(vm: ZreeViewModel) {
    val state by vm.state.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(state.message, state.error) {
        val text = state.error ?: state.message
        if (text != null) {
            snackbar.showSnackbar(text)
            vm.dismissMessage()
        }
    }

    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding ->
                Box(Modifier.padding(padding)) {
                    when (state.screen) {
                        Screen.Setup -> SetupScreen(vm, state)
                        Screen.List -> ListScreen(vm, state)
                        Screen.Editor -> EditorScreen(vm, state)
                    }
                }
            }
        }
    }
}
