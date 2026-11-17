# Named sift-cli because Homebrew core already has an unrelated `sift` formula.
class SiftCli < Formula
  desc "Clean developer caches, project artifacts, and disk clutter from the terminal"
  homepage "https://github.com/BadryansahBangsawan/Sift"
  url "https://github.com/BadryansahBangsawan/Sift/releases/download/cli-v1.1.1/sift-cli-1.1.1.tar.gz"
  sha256 "c4ae4ae7fb04a7d02b73d9f95a578ebf4c2f3636985d4966581818d3d8d5bcb2"
  license "MIT"

  depends_on macos: :big_sur

  def install
    bin.install "sift-cli"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/sift-cli --version")
  end
end
