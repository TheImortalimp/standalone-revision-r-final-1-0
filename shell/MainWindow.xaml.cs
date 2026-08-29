using Microsoft.Web.WebView2.Core;
using System.Diagnostics;
using System.IO;
using System.Windows;

namespace StandaloneRevisionRFinal;

public partial class MainWindow : Window
{
    private const string AppHost = "player.local";

    public MainWindow()
    {
        InitializeComponent();
        Loaded += InitializePlayerAsync;
    }

    private async void InitializePlayerAsync(object sender, RoutedEventArgs eventArgs)
    {
        try
        {
            var userDataPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TheImortalimp",
                "StandaloneRevisionRFinal",
                "WebView2");
            Directory.CreateDirectory(userDataPath);
            var environment = await CoreWebView2Environment.CreateAsync(null, userDataPath);
            await PlayerView.EnsureCoreWebView2Async(environment);

            var webUiPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "webui"));
            if (!Directory.Exists(webUiPath))
            {
                webUiPath = Path.Combine(AppContext.BaseDirectory, "webui");
            }
            if (!File.Exists(Path.Combine(webUiPath, "glitch-canvas-v-sync.html")))
            {
                MessageBox.Show("The bundled player files are missing.", Title, MessageBoxButton.OK, MessageBoxImage.Error);
                Close();
                return;
            }

            PlayerView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                AppHost,
                webUiPath,
                CoreWebView2HostResourceAccessKind.DenyCors);
            PlayerView.CoreWebView2.NewWindowRequested += BlockNewWindows;
            PlayerView.CoreWebView2.NavigationStarting += RestrictTopLevelNavigation;
            PlayerView.CoreWebView2.Navigate($"https://{AppHost}/glitch-canvas-v-sync.html");
        }
        catch (Exception exception)
        {
            var diagnosticPath = Path.Combine(AppContext.BaseDirectory, "startup-error.log");
            File.WriteAllText(diagnosticPath, exception.ToString());
            MessageBox.Show($"Unable to start the media player shell.\n\n{exception.Message}", Title, MessageBoxButton.OK, MessageBoxImage.Error);
            Close();
        }
    }

    private static void BlockNewWindows(object? sender, CoreWebView2NewWindowRequestedEventArgs eventArgs)
    {
        eventArgs.Handled = true;
    }

    private static void RestrictTopLevelNavigation(object? sender, CoreWebView2NavigationStartingEventArgs eventArgs)
    {
        if (!Uri.TryCreate(eventArgs.Uri, UriKind.Absolute, out var uri))
        {
            eventArgs.Cancel = true;
            return;
        }

        var host = uri.Host.ToLowerInvariant();
        var isAppPage = uri.Scheme == Uri.UriSchemeHttps && host == AppHost;
        if (uri.Scheme == Uri.UriSchemeHttps && host == "www.imortalimp.nl")
        {
            eventArgs.Cancel = true;
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
            return;
        }
        var isYouTube = uri.Scheme == Uri.UriSchemeHttps &&
            (host == "youtube.com" || host.EndsWith(".youtube.com", StringComparison.Ordinal) || host == "youtu.be");
        eventArgs.Cancel = !isAppPage && !isYouTube;
    }
}