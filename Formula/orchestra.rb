class Orchestra < Formula
  desc "AI-powered Git worktree and tmux session manager with modern TUI"
  homepage "https://github.com/humanunsupervised/orchestra"
  version "0.5.62"
  license "Proprietary"

  # Binary-only distribution - downloads pre-compiled packages
  if OS.mac? && Hardware::CPU.intel?
    url "https://github.com/humanunsupervised/orchestra/releases/download/v#{version}/orchestra-macos-intel.tar.gz"
    sha256 "ccab808f887c94e43688df2ef4f7a59da1192cdd618660943ee5012276c3444c"
  elsif OS.mac? && Hardware::CPU.arm?
    url "https://github.com/humanunsupervised/orchestra/releases/download/v#{version}/orchestra-macos-arm64.tar.gz"
    sha256 "3fb5d7f1420f99257e9748df13e4db210f3a7fac0f482d488ec74bf138f285f7"
  elsif OS.linux? && Hardware::CPU.intel?
    url "https://github.com/humanunsupervised/orchestra/releases/download/v#{version}/orchestra-linux-x64.tar.gz"
    sha256 "bf9d48cd08d136d1f048a7630a364c5e5d02ce816ff976334bac008586a2dd21"
  else
    odie "Orchestra is not available for #{OS.kernel_name} #{Hardware::CPU.arch}"
  end

  depends_on "git"
  depends_on "tmux" => :recommended
  depends_on "jq"

  def install
    # Install pre-compiled binary (renamed from gw-tui in the package)
    bin.install "orchestra" => "orchestra-bin"
    
    # Install runtime scripts to libexec
    libexec.install "gwr.sh"
    libexec.install "gw.sh"
    libexec.install "gw-bridge.sh"
    libexec.install "commands.sh"
    libexec.install "gw-env-copy"
    libexec.install "orchestra-local.sh"
    
    # Install API scripts
    (libexec/"api").mkpath
    (libexec/"api").install "api/git.sh"
    (libexec/"api").install "api/tmux.sh"
    
    # Create wrapper scripts that set correct paths
    (bin/"gwr").write wrapper_script("gwr.sh")
    (bin/"gw").write wrapper_script("gw.sh")
    
    # Create primary orchestra command (same as gwr for TUI interface)
    (bin/"orchestra").write orchestra_wrapper_script()
    
    (bin/"orchestra-local").write <<~EOS
      #!/bin/bash
      exec "#{libexec}/orchestra-local.sh" "$@"
    EOS
    (bin/"orchestra-local").chmod 0555
  end

  def wrapper_script(script_name)
    <<~EOS
      #!/bin/bash
      export GW_ORCHESTRATOR_ROOT="#{libexec}"
      export GW_TUI_BIN="#{bin}/orchestra-bin"
      export GW_ENV_COPY_BIN="#{libexec}/gw-env-copy"
      exec "#{libexec}/#{script_name}" "$@"
    EOS
  end

  def orchestra_wrapper_script
    <<~EOS
      #!/bin/bash
      # Orchestra wrapper with hanging fix
      export GW_ORCHESTRATOR_ROOT="#{libexec}"
      export GW_TUI_BIN="#{bin}/orchestra-bin"
      export GW_ENV_COPY_BIN="#{libexec}/gw-env-copy"
      
      # Fixed wrapper logic - routes commands to avoid stdout capture hanging
      case "${1:-}" in
        ""|"--debug"|"-d"|"--help"|"-h"|"--version")
          # Interactive TUI operations - run directly to avoid stdout capture
          exec "#{libexec}/gwr.sh" "$@"
          ;;
        *)
          # CLI operations that may need directory switching
          tmpfile="$(mktemp)"
          trap "rm -f '$tmpfile'" EXIT
          
          # Run CLI command and capture output in temp file
          "#{libexec}/gw.sh" "$@" > "$tmpfile" 2>&1
          status=$?
          
          # Handle directory switching
          out="$(cat "$tmpfile")"
          cd_line="$(echo "$out" | grep -m1 '^cd')"
          [[ -n $cd_line ]] && eval "$cd_line"
          
          # Show output excluding cd commands  
          echo "$out" | grep -v '^cd'
          exit $status
          ;;
      esac
    EOS
  end

  def caveats
    <<~EOS
      Orchestra is ready to use! Type `orchestra` in your repo root to start.
    EOS
  end

  test do
    # Test that the binary exists and is executable
    assert_predicate bin/"orchestra-bin", :exist?
    assert_predicate bin/"orchestra-bin", :executable?
    
    # Test that wrapper scripts are accessible
    assert_predicate bin/"orchestra", :exist?
    assert_predicate bin/"gwr", :exist?
    assert_predicate bin/"gw", :exist?
    assert_predicate bin/"orchestra-local", :exist?
    
    # Test basic help output (in a safe way)
    output = shell_output("#{bin}/gw help 2>&1", 0)
    assert_match(/Usage|Commands|Options/, output)
  end
end
