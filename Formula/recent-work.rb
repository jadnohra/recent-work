class RecentWork < Formula
  desc "Monitors file writes and maintains a Finder-friendly folder of symlinks to recent files"
  homepage "https://github.com/yourusername/recent-work"
  url "https://github.com/yourusername/recent-work/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "UPDATE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on xcode: ["14.0", :build]
  depends_on :macos

  def install
    system "swift", "build",
           "-c", "release",
           "--disable-sandbox",
           "-Xswiftc", "-cross-module-optimization"
    bin.install ".build/release/recent-work"
  end

  def caveats
    <<~EOS
      To set up recent-work:
        recent-work init

      To start the daemon:
        recent-work start

      To run manually in the foreground:
        recent-work start --foreground

      Configuration is stored in:
        ~/.config/recent-work/config.toml

      Recent files will appear in:
        ~/RecentWork/
    EOS
  end

  test do
    system "#{bin}/recent-work", "--help"
  end
end
