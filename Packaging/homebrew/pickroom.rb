class Pickroom < Formula
  desc "Keyboard-first RAW culling workspace for macOS"
  homepage "https://github.com/zjywill/Pickroom"
  url "ssh://git@github.com/zjywill/Pickroom.git",
      tag:      "v__VERSION__",
      revision: "__REVISION__"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
    strategy :git
  end

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  def install
    ENV["OUTER_SANDBOX"] = "1"
    ENV["UNIVERSAL"] = "0"
    ENV["DMG"] = "0"
    ENV["DEST"] = buildpath/"dist"
    ENV["VERSION"] = version.to_s
    system "./scripts/bundle.sh"

    prefix.install "dist/Pickroom.app"
    (bin/"pickroom").write <<~SH
      #!/bin/bash
      exec "#{opt_prefix}/Pickroom.app/Contents/MacOS/Pickroom" "$@"
    SH
  end

  def caveats
    <<~EOS
      Pickroom.app was installed to:
        #{opt_prefix}/Pickroom.app

      Put a real copy in Applications so Finder, Launchpad, and Spotlight see it:
        rm -rf /Applications/Pickroom.app
        cp -R #{opt_prefix}/Pickroom.app /Applications/Pickroom.app

      Repeat the copy after each upgrade, with Pickroom quit first.
    EOS
  end

  test do
    app = prefix/"Pickroom.app"
    assert_path_exists app/"Contents/MacOS/Pickroom"
    system "/usr/bin/codesign", "--verify", "--deep", "--strict", app
    assert_match "com.junyizhang.Pickroom",
                 shell_output("/usr/bin/defaults read #{app}/Contents/Info CFBundleIdentifier")
  end
end
