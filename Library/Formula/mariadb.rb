class Mariadb < Formula
  desc "Drop-in replacement for MySQL"
  homepage "https://mariadb.org/"
  url "http://ftp.osuosl.org/pub/mariadb/mariadb-10.0.20/source/mariadb-10.0.20.tar.gz"
  sha256 "3a4f6963c794977af5d5fd9ec06a337a2ad556b3a287196fddbd2243c1388b7b"

  bottle do
    sha256 "66f51ca674ca5e82f1d813507382f9b448f4a96e2de472b9be3297d090780348" => :yosemite
    sha256 "848299d2e682d2cc353be6119e90ba2670a03361cdbe868f89c6143a838b422e" => :mavericks
    sha256 "3f760e604dbee14a52e854ab8c85dcb3e68c53652750917eaa90d8e463d8958f" => :mountain_lion
  end

  devel do
    url "http://ftp.osuosl.org/pub/mariadb/mariadb-10.1.5/source/mariadb-10.1.5.tar.gz"
    sha256 "af8788bfbb842338882e505612f86ef53a25968663a1519185ecf3de3b1efe83"
  end

  depends_on "cmake" => :build
  depends_on "pidof" unless MacOS.version >= :mountain_lion
  depends_on "openssl"

  option :universal
  option "with-tests", "Keep test when installing"
  option "with-bench", "Keep benchmark app when installing"
  option "with-embedded", "Build the embedded server"
  option "with-libedit", "Compile with editline wrapper instead of readline"
  option "with-archive-storage-engine", "Compile with the ARCHIVE storage engine enabled"
  option "with-blackhole-storage-engine", "Compile with the BLACKHOLE storage engine enabled"
  option "with-local-infile", "Build with local infile loading support"

  deprecated_option "enable-local-infile" => "with-local-infile"

  conflicts_with "mysql", "mysql-cluster", "percona-server",
    :because => "mariadb, mysql, and percona install the same binaries."
  conflicts_with "mysql-connector-c",
    :because => "both install MySQL client libraries"

  def install
    # Don't hard-code the libtool path. See:
    # https://github.com/Homebrew/homebrew/issues/20185
    inreplace "cmake/libutils.cmake",
      "COMMAND /usr/bin/libtool -static -o ${TARGET_LOCATION}",
      "COMMAND libtool -static -o ${TARGET_LOCATION}"

    # Set basedir and ldata so that mysql_install_db can find the server
    # without needing an explicit path to be set. This can still
    # be overridden by calling --basedir= when calling.
    inreplace "scripts/mysql_install_db.sh" do |s|
      s.change_make_var! "basedir", "\"#{prefix}\""
      s.change_make_var! "ldata", "\"#{var}/mysql\""
    end

    # Build without compiler or CPU specific optimization flags to facilitate
    # compilation of gems and other software that queries `mysql-config`.
    ENV.minimal_optimization

    # -DINSTALL_* are relative to prefix
    args = %W[
      .
      -DCMAKE_INSTALL_PREFIX=#{prefix}
      -DCMAKE_FIND_FRAMEWORK=LAST
      -DCMAKE_VERBOSE_MAKEFILE=ON
      -DMYSQL_DATADIR=#{var}/mysql
      -DINSTALL_INCLUDEDIR=include/mysql
      -DINSTALL_MANDIR=share/man
      -DINSTALL_DOCDIR=share/doc/#{name}
      -DINSTALL_INFODIR=share/info
      -DINSTALL_MYSQLSHAREDIR=share/mysql
      -DWITH_SSL=yes
      -DDEFAULT_CHARSET=utf8
      -DDEFAULT_COLLATION=utf8_general_ci
      -DINSTALL_SYSCONFDIR=#{etc}
      -DCOMPILATION_COMMENT=Homebrew
    ]

    # disable TokuDB, which is currently not supported on Mac OS X
    if build.stable?
      args << "-DWITHOUT_TOKUDB=1"
    else
      args << "-DPLUGIN_TOKUDB=NO"
    end

    args << "-DWITH_UNIT_TESTS=OFF" if build.without? "tests"

    # Build the embedded server
    args << "-DWITH_EMBEDDED_SERVER=ON" if build.with? "embedded"

    # Compile with readline unless libedit is explicitly chosen
    args << "-DWITH_READLINE=yes" if build.without? "libedit"

    # Compile with ARCHIVE engine enabled if chosen
    if build.with? "archive-storage-engine"
      if build.stable?
        args << "-DWITH_ARCHIVE_STORAGE_ENGINE=1"
      else
        args << "-DPLUGIN_ARCHIVE=YES"
      end
    end

    # Compile with BLACKHOLE engine enabled if chosen
    if build.with? "blackhole-storage-engine"
      if build.stable?
        args << "-DWITH_BLACKHOLE_STORAGE_ENGINE=1"
      else
        args << "-DPLUGIN_BLACKHOLE=YES"
      end
    end

    # Make universal for binding to universal applications
    if build.universal?
      ENV.universal_binary
      args << "-DCMAKE_OSX_ARCHITECTURES=#{Hardware::CPU.universal_archs.as_cmake_arch_flags}"
    end

    # Build with local infile loading support
    args << "-DENABLED_LOCAL_INFILE=1" if build.with? "local-infile"

    system "cmake", *args
    system "make"
    system "make", "install"

    # Fix my.cnf to point to #{etc} instead of /etc
    (etc+"my.cnf.d").mkpath
    inreplace "#{etc}/my.cnf" do |s|
      s.gsub!("!includedir /etc/my.cnf.d", "!includedir #{etc}/my.cnf.d")
    end
    touch etc/"my.cnf.d/.homebrew_dont_prune_me"

    # Don't create databases inside of the prefix!
    # See: https://github.com/Homebrew/homebrew/issues/4975
    rm_rf prefix+"data"

    (prefix+"mysql-test").rmtree if build.without? "tests" # save 121MB!
    (prefix+"sql-bench").rmtree if build.without? "bench"

    # Link the setup script into bin
    bin.install_symlink prefix/"scripts/mysql_install_db"

    # Fix up the control script and link into bin
    inreplace "#{prefix}/support-files/mysql.server" do |s|
      s.gsub!(/^(PATH=".*)(")/, "\\1:#{HOMEBREW_PREFIX}/bin\\2")
      # pidof can be replaced with pgrep from proctools on Mountain Lion
      s.gsub!(/pidof/, "pgrep") if MacOS.version >= :mountain_lion
    end

    bin.install_symlink prefix/"support-files/mysql.server"

    if build.devel?
      # Move sourced non-executable out of bin into libexec
      libexec.mkpath
      libexec.install "#{bin}/wsrep_sst_common"
      # Fix up references to wsrep_sst_common
      %W[
        wsrep_sst_mysqldump
        wsrep_sst_rsync
        wsrep_sst_xtrabackup
        wsrep_sst_xtrabackup-v2
      ].each do |f|
        inreplace "#{bin}/#{f}" do |s|
          s.gsub!("$(dirname $0)/wsrep_sst_common", "#{libexec}/wsrep_sst_common")
        end
      end
    end
  end

  def post_install
    # Make sure the var/mysql directory exists
    (var+"mysql").mkpath
    unless File.exist? "#{var}/mysql/mysql/user.frm"
      ENV["TMPDIR"] = nil
      system "#{bin}/mysql_install_db", "--verbose", "--user=#{ENV["USER"]}",
        "--basedir=#{prefix}", "--datadir=#{var}/mysql", "--tmpdir=/tmp"
    end
  end

  def caveats; <<-EOS.undent
    A "/etc/my.cnf" from another install may interfere with a Homebrew-built
    server starting up correctly.

    To connect:
        mysql -uroot
    EOS
  end

  plist_options :manual => "mysql.server start"

  def plist; <<-EOS.undent
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>KeepAlive</key>
      <true/>
      <key>Label</key>
      <string>#{plist_name}</string>
      <key>ProgramArguments</key>
      <array>
        <string>#{opt_bin}/mysqld_safe</string>
        <string>--bind-address=127.0.0.1</string>
        <string>--datadir=#{var}/mysql</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>WorkingDirectory</key>
      <string>#{var}</string>
    </dict>
    </plist>
    EOS
  end

  test do
    if build.with? "tests"
      (prefix+"mysql-test").cd do
        system "./mysql-test-run.pl", "status"
      end
    else
      system "mysqld", "--version"
    end
  end
end
