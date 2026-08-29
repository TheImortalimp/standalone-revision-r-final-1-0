using Microsoft.Web.WebView2.Core;
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
            await PlayerView.EnsureCoreWebView2Async();

            var webUiPath = Path.Combine(AppContext.BaseDirectory, "webui");
            if (!File.Exists(Path.Combine(webUiPath, "glitch-canvas-youtube.html")))
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
            PlayerView.CoreWebView2.Navigate($"https://{AppHost}/glitch-canvas-youtube.html");
        }
        catch (Exception exception)
        {
            MessageBox.Show($"Unable to start the YouTube player shell.\n\n{exception.Message}", Title, MessageBoxButton.OK, MessageBoxImage.Error);
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
        var isYouTube = uri.Scheme == Uri.UriSchemeHttps &&
            (host == "youtube.com" || host.EndsWith(".youtube.com", StringComparison.Ordinal) || host == "youtu.be");
        eventArgs.Cancel = !isAppPage && !isYouTube;
    }
}