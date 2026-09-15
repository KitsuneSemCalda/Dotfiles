#!/usr/bin/env perl
use 5.036;
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy move);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use Getopt::Long qw(GetOptions);
use POSIX qw(strftime);

my $dry_run = 0;
my $backup  = 0;
my $restore = 0;
my $apps    = 0;
my $fonts   = 0;
my $plugin  = 0;
my $theme   = 0;
my $all     = 0;
my $help    = 0;
my $target  = $ENV{HOME};

GetOptions(
    'dry-run'  => \$dry_run,
    'backup'   => \$backup,
    'restore'  => \$restore,
    'apps'     => \$apps,
    'fonts'    => \$fonts,
    'plugin'   => \$plugin,
    'theme'    => \$theme,
    'all'      => \$all,
    'target=s' => \$target,
    'help'     => \$help,
) or usage(2);

usage(0) if $help;

$apps = $fonts = $plugin = $theme = 1 if $all;

if ($restore && ($backup || $apps || $fonts || $plugin || $theme)) {
    die "--restore cannot be combined with --backup, --apps, --fonts, --plugin, --theme, or --all\n";
}

die "HOME is not set; use --target PATH\n"
    unless defined $target && length $target;

my $script_dir  = dirname(__FILE__);
$script_dir     = File::Spec->rel2abs($script_dir) unless File::Spec->file_name_is_absolute($script_dir);
my $repo_root   = $script_dir;
die "Could not locate the repository\n" unless -d $repo_root;
my $source_root = File::Spec->catdir($repo_root, 'home');
$target         = abs_path($target) // File::Spec->rel2abs($target);

die "Missing source directory: $source_root\n" unless -d $source_root;
die "Missing destination: $target\n" unless -d $target;

my $home_root = abs_path($ENV{HOME} // '') // '';
if (($apps || $fonts || $plugin || $theme) && $target ne $home_root) {
    die "Omarchy actions can only use the real HOME; use --target only to test symlinks\n";
}

my $backup_base = File::Spec->catdir($target, '.local', 'state', 'dotfiles', 'backups');

if ($restore) {
    restore_backups($backup_base);
    exit 0;
}

my $stamp       = strftime('%Y%m%d-%H%M%S', localtime);
my $backup_root = File::Spec->catdir($backup_base, $stamp);
my @sources;

find(
    {
        no_chdir => 1,
        wanted   => sub {
            push @sources, $File::Find::name if -f $File::Find::name;
        },
    },
    $source_root,
);

my $failures = 0;
for my $source (sort @sources) {
    my $relative    = File::Spec->abs2rel($source, $source_root);
    my $destination = File::Spec->catfile($target, $relative);
    my $parent      = dirname($destination);

    if (-l $destination) {
        my $link       = readlink($destination);
        my $link_abs   = defined $link ? File::Spec->rel2abs($link, $parent) : '';
        my $source_abs = abs_path($source);
        if (defined $link && $link_abs eq $source_abs) {
            say "OK      $relative";
            next;
        }
    }

    if (-e $destination || -l $destination) {
        if (-d $destination && !-l $destination) {
            warn "CONFLICT $relative (it's a directory; will not be moved automatically)\n";
            $failures++;
            next;
        }
        unless ($backup) {
            warn "CONFLICT $relative (use --backup to preserve the original)\n";
            $failures++;
            next;
        }

        my $backup_path = File::Spec->catfile($backup_root, $relative);
        say "BACKUP  $relative -> " . File::Spec->abs2rel($backup_path, $target);
        make_path(dirname($backup_path)) unless $dry_run || -d dirname($backup_path);
        move($destination, $backup_path) unless $dry_run;
        die "Failed to move $destination to $backup_path: $!\n"
            unless $dry_run || -e $backup_path || -l $backup_path;
    }

    say(($dry_run ? 'LINK?   ' : 'LINK    ') . "$relative -> $source");
    next if $dry_run;

    make_path($parent) unless -d $parent;
    symlink($source, $destination)
        or die "Failed to create symlink $destination: $!\n";
}

die "$failures conflict(s) found; nothing conflicting was overwritten\n" if $failures;

ensure_fonts()  if $fonts;
ensure_apps()   if $apps;
ensure_plugin() if $plugin;
ensure_theme()  if $theme;

say $dry_run ? 'Dry-run finished.' : 'Dotfiles installed.';
exit 0;

sub restore_backups {
    my ($backup_base) = @_;

    opendir my $backup_dir, $backup_base
        or die "Missing backups directory: $backup_base\n";

    my @snapshots = sort grep {
        /^\d{8}-\d{6}$/ && -d File::Spec->catdir($backup_base, $_)
    } readdir $backup_dir;
    closedir $backup_dir;

    my $snapshot_name = $snapshots[-1]
        or die "No backup found in $backup_base\n";
    my $snapshot = File::Spec->catdir($backup_base, $snapshot_name);
    my @entries;

    find(
        {
            no_chdir => 1,
            wanted   => sub {
                push @entries, $File::Find::name
                    if -f $File::Find::name || -l $File::Find::name;
            },
        },
        $snapshot,
    );

    die "Backup $snapshot_name contains no restorable files\n"
        unless @entries;

    my (@actions, @conflicts);
    for my $backup_path (sort @entries) {
        my $relative    = File::Spec->abs2rel($backup_path, $snapshot);
        my $destination = File::Spec->catfile($target, $relative);
        my $occupied    = -e $destination || -l $destination;

        if ($occupied && !points_to_source($destination, $relative)) {
            push @conflicts, $relative;
            next;
        }

        push @actions, {
            backup_path => $backup_path,
            destination => $destination,
            relative    => $relative,
        };
    }

    if (@conflicts) {
        warn "CONFLICT $_ (the destination is not a symlink from these dotfiles)\n"
            for @conflicts;
        die scalar(@conflicts) . " conflict(s); restore aborted without changing files\n";
    }

    say "BACKUP   $snapshot_name";
    for my $action (@actions) {
        my $relative_backup = File::Spec->abs2rel($action->{backup_path}, $target);
        say(($dry_run ? 'RESTORE? ' : 'RESTORE  ')
            . "$action->{relative} <- $relative_backup");
        next if $dry_run;

        unlink $action->{destination}
            if -e $action->{destination} || -l $action->{destination};
        restore_entry($action->{backup_path}, $action->{destination});
    }

    say $dry_run
        ? 'Restore dry-run finished.'
        : "Backup restored; copy preserved at $snapshot";
}

sub points_to_source {
    my ($destination, $relative) = @_;
    return 0 unless -l $destination;

    my $link = readlink($destination);
    return 0 unless defined $link;

    my $link_abs = File::Spec->canonpath(
        File::Spec->rel2abs($link, dirname($destination))
    );
    my $source_abs = File::Spec->canonpath(
        File::Spec->rel2abs(File::Spec->catfile($source_root, $relative))
    );

    return $link_abs eq $source_abs;
}

sub restore_entry {
    my ($backup_path, $destination) = @_;
    my $parent = dirname($destination);
    make_path($parent) unless -d $parent;

    if (-l $backup_path) {
        my $link = readlink($backup_path);
        die "Could not read the backup symlink $backup_path\n"
            unless defined $link;
        symlink($link, $destination)
            or die "Failed to restore symlink $destination: $!\n";
        return;
    }

    copy($backup_path, $destination)
        or die "Failed to copy $backup_path to $destination: $!\n";
}

sub ensure_fonts {
    ensure_lexend_font();

    if (font_present('Lexend')) {
        say 'FONT    Lexend available';
    } elsif ($dry_run) {
        say 'FONT?   Lexend will be used after the files are downloaded';
    } else {
        die "Lexend was not found after downloading the files\n";
    }
}

sub ensure_lexend_font {
    my $font_dir = File::Spec->catdir($target, '.local', 'share', 'fonts', 'lexend');
    my %weight_of_file = (
        'Lexend-Regular.ttf' => 400,
        'Lexend-Bold.ttf'    => 700,
    );

    if (!grep { !-f File::Spec->catfile($font_dir, $_) } keys %weight_of_file) {
        say 'OK      Lexend font files already downloaded';
        return;
    }

    if ($dry_run) {
        say 'FONT?   Lexend would be downloaded from Google Fonts to ' . $font_dir;
        return;
    }

    make_path($font_dir) unless -d $font_dir;

    # A generic user-agent makes the Google Fonts API respond with TrueType
    # (instead of woff2), which is the format fontconfig/Linux expects.
    my $css = qx{curl -sL -A 'Mozilla/5.0' 'https://fonts.googleapis.com/css2?family=Lexend:wght\@400;700'};
    die "Could not fetch the Google Fonts CSS for Lexend\n" unless $css;

    my %url_of_weight;
    while ($css =~ /font-weight:\s*(\d+);\s*\n\s*src:\s*url\(([^)]+)\)/g) {
        $url_of_weight{$1} = $2;
    }

    for my $file (sort keys %weight_of_file) {
        my $weight = $weight_of_file{$file};
        my $url    = $url_of_weight{$weight}
            or die "Lexend font URL (weight $weight) not found in the Google Fonts CSS\n";
        run_command('curl', '-sL', $url, '-o', File::Spec->catfile($font_dir, $file));
    }

    run_command('fc-cache', '-f', $font_dir);
}

sub ensure_apps {
    for my $name ('HEY', 'Basecamp') {
        if (webapp_present($name)) {
            run_command('omarchy', 'webapp', 'remove', $name);
        } else {
            say "SKIP    web app $name is not installed";
        }
    }

    my $onepassword_extension = '/usr/share/chromium/extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa.json';
    if (package_present('1password') || package_present('1password-cli') || -e $onepassword_extension) {
        run_command('omarchy', 'remove', 'service', '1password');
    } else {
        say 'SKIP    1Password is not installed';
    }

    ensure_repo_packages('prismlauncher');
    ensure_aur_packages('bitwarden-bin', 'appflowy-bin', 'curseforge');

    my @webapps = (
        { name => 'Amazon Shopping', url => 'https://www.amazon.com.br' },
        { name => 'Mercado Livre',    url => 'https://mercadolivre.com.br' },
        { name => 'Pinterest',        url => 'https://br.pinterest.com/' },
        { name => 'Z Ai',             url => 'https://chat.z.ai/' },
        { name => 'WebMotors',        url => 'https://www.webmotors.com.br/' },
        { name => 'Panini Brasil',    url => 'https://panini.com.br/' },
        { name => 'GitHub',           url => 'https://github.com/' },
        { name => 'GitLab',           url => 'https://gitlab.com/' },
        { name => 'Codeberg',         url => 'https://codeberg.org/' },
        { name => 'Copilot',          url => 'https://github.com/copilot' },
        { name => 'Claude',           url => 'https://claude.ai/' },
        { name => 'ChatGPT',          url => 'https://chatgpt.com/' },
        { name => 'Grok',             url => 'https://grok.com/' },
        { name => 'Gemini',           url => 'https://gemini.google.com/' },
    );

    for my $app (@webapps) {
        if (webapp_present($app->{name})) {
            say "OK      web app $app->{name}";
            next;
        }

        # The empty argument makes the official installer fetch the site's icon.
        run_command('omarchy', 'webapp', 'install', $app->{name}, $app->{url}, '');
    }
}

sub ensure_plugin {
    my $id  = 'io.github.kitsunesemcalda.feader-rss';
    my $url = 'https://github.com/KitsuneSemCalda/Feader-RSS.git';
    my $dir = File::Spec->catdir($target, '.config', 'omarchy', 'plugins', $id);

    if (-d $dir) {
        say "OK      plugin $id is already installed";
        run_command('omarchy', 'plugin', 'enable', $id, 'right');
    } else {
        # No --yes: Omarchy shows the security confirmation for code that
        # will run inside the shell's persistent process.
        run_command('omarchy', 'plugin', 'add', $url, '--enable');
    }
}

sub ensure_theme {
    my $url = 'https://github.com/KitsuneSemCalda/Sword-Art-Omarchy';
    my $dir = File::Spec->catdir($target, '.config', 'omarchy', 'themes', 'sword-art-omarchy');

    # A previous local checkout may have left a dangling symlink. Preserve it
    # before the official installer clones the theme into the same path.
    if (-l $dir && !-e $dir) {
        my $link_backup = File::Spec->catfile(
            $backup_root,
            '.config',
            'omarchy',
            'themes',
            'sword-art-omarchy',
        );
        say "THEME-BACKUP $dir -> " . File::Spec->abs2rel($link_backup, $target);
        unless ($dry_run) {
            make_path(dirname($link_backup));
            move($dir, $link_backup)
                or die "Failed to preserve the theme symlink: $!\n";
        }
    }

    if (-d $dir) {
        say 'OK      Sword Art Omarchy theme already installed';
    } else {
        run_command('omarchy', 'theme', 'install', $url);
    }

    run_command('omarchy', 'theme', 'set', 'Sword Art Omarchy');
}

sub ensure_repo_packages {
    my @packages = @_;
    my @missing  = grep { !package_present($_) } @packages;
    if (@missing) {
        run_command('omarchy', 'pkg', 'add', @missing);
    } else {
        say 'OK      official packages already installed: ' . join(', ', @packages);
    }
}

sub ensure_aur_packages {
    my @packages = @_;
    my @missing  = grep { !package_present($_) } @packages;
    if (@missing) {
        run_command('omarchy', 'pkg', 'aur', 'add', @missing);
    } else {
        say 'OK      AUR packages already installed: ' . join(', ', @packages);
    }
}

sub package_present {
    my ($package) = @_;

    # `pacman -Qq missing-package` writes an error to stderr; keep the
    # detection quiet so dry-runs remain readable.
    open my $saved_stderr, '>&', \*STDERR or return 0;
    open STDERR, '>', File::Spec->devnull() or return 0;
    my $query;
    unless (open $query, '-|', 'pacman', '-Qq', $package) {
        open STDERR, '>&', $saved_stderr;
        return 0;
    }
    <$query>;
    my $present = close $query;
    open STDERR, '>&', $saved_stderr or die "Could not restore stderr\n";
    return $present;
}

sub font_present {
    my ($family) = @_;
    open my $match, '-|', 'fc-match', '-f', '%{family}\n', $family or return 0;
    my $result = <$match> // '';
    close $match;
    return $result =~ /\Q$family\E/i;
}

sub webapp_present {
    my ($name) = @_;
    my $desktop = File::Spec->catfile($target, '.local', 'share', 'applications', "$name.desktop");
    return 0 unless -f $desktop;

    open my $file, '<', $desktop or return 0;
    local $/;
    my $content = <$file> // '';
    close $file;
    return $content =~ /^Exec=.*(?:omarchy-launch-webapp|omarchy-webapp-handler)/m;
}

sub run_command {
    my (@command) = @_;
    my $display = join(' ', map { shell_quote($_) } @command);
    if ($dry_run) {
        say "RUN?    $display";
        return;
    }

    say "RUN     $display";
    my $status = system(@command);
    die "Command failed ($status): $display\n" if $status == -1 || $status != 0;
}

sub shell_quote {
    my ($value) = @_;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub usage {
    my ($status) = @_;
    print <<'USAGE';
Usage: perl omarchy.pl [options]

  --dry-run          shows the actions without creating links or running commands
  --backup           moves conflicts to ~/.local/state/dotfiles/backups/
  --restore          restores the most recent backup without deleting the copy
  --apps             removes old items and installs the requested apps/web apps
  --fonts            installs Lexend and enables the font profile
  --plugin           installs/enables Feader-RSS
  --theme            installs/applies the Sword Art Omarchy theme
  --all              runs --apps --fonts --plugin --theme
  --target PATH      uses a different root directory only to test symlinks
  --help             shows this help
USAGE
    exit $status;
}
