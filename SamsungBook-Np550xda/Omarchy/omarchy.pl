#!/usr/bin/env perl
use 5.036;
use strict;
use warnings;

use Cwd qw(abs_path);
use Digest::SHA ();
use JSON::PP qw(encode_json decode_json);
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
my $omastore = 0;
my $reboot = 0;
my $theme   = 0;
my $openrgb = 0;
my $all     = 0;
my $help    = 0;
my $target  = $ENV{HOME};

GetOptions(
    'dry-run'  => \$dry_run,
    'backup'   => \$backup,
    'restore'  => \$restore,
    'apps'     => \$apps,
    'fonts'    => \$fonts,
    'plugin|plugins' => \$plugin,
    'omastore' => \$omastore,
    'reboot'   => \$reboot,
    'theme'    => \$theme,
    'openrgb'  => \$openrgb,
    'all'      => \$all,
    'target=s' => \$target,
    'help'     => \$help,
) or usage(2);

usage(0) if $help;

$apps = $fonts = $plugin = $theme = $openrgb = 1 if $all;
$omastore = 1 if $all || $plugin;

if ($restore && ($backup || $apps || $fonts || $plugin || $theme || $openrgb || $omastore || $reboot)) {
    die "--restore cannot be combined with installation actions or --reboot\n";
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
if (($apps || $fonts || $plugin || $theme || $openrgb || $omastore || $reboot) && $target ne $home_root) {
    die "Omarchy actions can only use the real HOME; use --target only to test file installation\n";
}

my $backup_base = File::Spec->catdir($target, '.local', 'state', 'dotfiles', 'backups');

my $state_path = File::Spec->catfile($target, '.local', 'state', 'dotfiles', 'installed.json');
my $installed = {};
if (-f $state_path) {
    open my $fh, '<', $state_path or die "Cannot read $state_path: $!";
    local $/;
    $installed = decode_json(<$fh>);
}

sub file_hash {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    return Digest::SHA->new(256)->addfile($fh)->hexdigest;
}

sub save_state {
    make_path(dirname($state_path));
    open my $fh, '>', "$state_path.tmp" or die "Cannot write state: $!";
    print {$fh} encode_json($installed);
    close $fh or die "Cannot close state: $!";
    rename "$state_path.tmp", $state_path or die "Cannot replace state: $!";
}

if ($restore) {
    restore_backups($backup_base);
    exit 0;
}

my $stamp       = strftime('%Y%m%d-%H%M%S', localtime);
my $backup_root;
my $plugin_backup_root;
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

# Passagem de validacao (somente leitura): monta o plano de acao para cada
# arquivo antes de tocar em qualquer coisa. Se houver conflito, aborta aqui
# sem ter criado nenhuma copia ou movido nenhum backup.
my (@plan, @conflicts);
for my $source (sort @sources) {
    my $relative    = File::Spec->abs2rel($source, $source_root);
    my $destination = File::Spec->catfile($target, $relative);

    if (points_to_source($destination, $relative)
        || (!-l $destination && -f $destination
            && defined $installed->{$relative}
            && file_hash($destination) eq $installed->{$relative})) {
        push @plan, { source => $source, destination => $destination,
            relative => $relative, action => 'copy' };
        next;
    }

    if (-e $destination || -l $destination) {
        if (-d $destination && !-l $destination) {
            push @conflicts, "$relative (it's a directory; will not be moved automatically)";
            next;
        }
        unless ($backup) {
            push @conflicts, "$relative (use --backup to preserve the original)";
            next;
        }

        push @plan, {
            source      => $source,
            destination => $destination,
            relative    => $relative,
            action      => 'backup_copy',
        };
        next;
    }

    push @plan, {
        source      => $source,
        destination => $destination,
        relative    => $relative,
        action      => 'copy',
    };
}

if (@conflicts) {
    warn "CONFLICT $_\n" for @conflicts;
    die scalar(@conflicts) . " conflict(s) found; validation failed and nothing was changed\n";
}

# Passagem de aplicacao: so comeca depois que a validacao inteira passou.
my @applied;
for my $item (@plan) {
    my $relative = $item->{relative};

    my ($source, $destination) = @{$item}{qw(source destination)};
    my $parent = dirname($destination);

    if ($item->{action} eq 'backup_copy') {
        $backup_root //= $dry_run
            ? File::Spec->catdir($backup_base, $stamp)
            : reserve_backup_root();
        my $backup_path = File::Spec->catfile($backup_root, $relative);
        say "BACKUP  $relative -> " . File::Spec->abs2rel($backup_path, $target);
        unless ($dry_run) {
            make_path(dirname($backup_path)) unless -d dirname($backup_path);
            move($destination, $backup_path)
                or apply_failure(\@applied, "Failed to move $destination to $backup_path: $!");
            push @applied, "BACKUP $relative";
        }
    }

    say(($dry_run ? 'COPY?   ' : 'COPY    ') . "$relative -> $source");
    next if $dry_run;

    make_path($parent) unless -d $parent;
    my $staged = "$destination.dotfiles-tmp-$$";
    copy($source, $staged)
        or apply_failure(\@applied, "Failed to copy $source: $!");
    chmod((stat($source))[2] & 0777, $staged)
        or apply_failure(\@applied, "Failed to set permissions: $!");
    rename($staged, $destination)
        or apply_failure(\@applied, "Failed to replace $destination: $!");
    $installed->{$relative} = file_hash($destination);
    save_state();
    push @applied, "COPY $relative";
}

if ($target eq $home_root) {
    ensure_skills();
} else {
    say 'SKIP    skill installation (using a test --target, not the real HOME)';
}

ensure_fonts()  if $fonts;
ensure_apps()   if $apps;
ensure_omastore() if $omastore;
ensure_plugin() if $plugin;
ensure_theme()  if $theme;
ensure_openrgb() if $openrgb;

if ($plugin || $reboot) {
    run_command('hyprctl', 'reload');
    unless ($dry_run) {
        my $errors = command_output('hyprctl', 'configerrors');
        die "Hyprland configuration errors; refusing reboot:\n$errors" if $errors =~ /\S/;
    }
}

say $dry_run ? 'Dry-run finished.' : 'Dotfiles installed.';
run_command('systemctl', 'reboot') if $reboot;
exit 0;

# Cria (atomicamente) um diretorio de backup exclusivo desta execucao.
sub reserve_backup_root {
    my ($base) = @_;
    $base //= $backup_base;
    make_path($base) unless -d $base;
    for my $n (0 .. 999) {
        my $name = $n ? sprintf('%s-%03d', $stamp, $n) : $stamp;
        my $dir  = File::Spec->catdir($base, $name);
        return $dir if mkdir $dir;
        die "Cannot create backup directory $dir: $!\n" unless $!{EEXIST};
    }
    die "Cannot reserve a unique backup directory under $base\n";
}

sub apply_failure {
    my ($applied, $message) = @_;
    my $summary = @$applied
        ? 'Changes already applied before the failure: ' . join(', ', @$applied) . '.'
        : 'No changes were applied before the failure.';
    die "$message\n$summary\n";
}

sub restore_backups {
    my ($backup_base) = @_;

    opendir my $backup_dir, $backup_base
        or die "Missing backups directory: $backup_base\n";

    my @snapshots = sort grep {
        /^\d{8}-\d{6}(?:-\d{3})?$/ && -d File::Spec->catdir($backup_base, $_)
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

        if ($occupied && !points_to_source($destination, $relative)
            && !(!-l $destination && -f $destination
                && defined $installed->{$relative}
                && file_hash($destination) eq $installed->{$relative})) {
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
        warn "CONFLICT $_ (the destination is not an unchanged installation)\n"
            for @conflicts;
        die scalar(@conflicts) . " conflict(s); restore aborted without changing files\n";
    }

    say "BACKUP   $snapshot_name";
    for my $action (@actions) {
        my $relative_backup = File::Spec->abs2rel($action->{backup_path}, $target);
        say(($dry_run ? 'RESTORE? ' : 'RESTORE  ')
            . "$action->{relative} <- $relative_backup");
        next if $dry_run;

        restore_entry($action->{backup_path}, $action->{destination});
        delete $installed->{$action->{relative}};
        save_state();
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

    my $staged = "$destination.dotfiles-tmp-$$";
    unlink $staged if -e $staged || -l $staged;

    if (-l $backup_path) {
        my $link = readlink($backup_path);
        die "Could not read the backup symlink $backup_path\n"
            unless defined $link;
        symlink($link, $staged)
            or die "Failed to restore symlink $destination: $!\n";
    } else {
        my $mode = (stat($backup_path))[2] & 07777;
        copy($backup_path, $staged)
            or die "Failed to copy $backup_path to $destination: $!\n";
        chmod($mode, $staged)
            or do { unlink $staged; die "Failed to set permissions on $staged: $!\n" };
    }

    rename($staged, $destination)
        or do { unlink $staged; die "Failed to replace $destination: $!\n" };
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
        { name => 'Amazon Shopping',  url => 'https://www.amazon.com.br' },
        { name => 'Mercado Livre',    url => 'https://mercadolivre.com.br' },
        { name => 'Instagram',        url => 'https://www.instagram.com/' },
        { name => 'Facebook',         url => 'https://www.facebook.com/' },
        { name => 'Twitch',           url => 'https://www.twitch.tv/' },
        { name => 'HBO Max',          url => 'https://play.hbomax.com/' },
        { name => 'TikTok',           url => 'https://www.tiktok.com/pt-BR/' },
        { name => 'Pinterest',        url => 'https://br.pinterest.com/' },
        { name => 'Reddit',           url => 'https://www.reddit.com/' },
        { name => 'Z Ai',             url => 'https://chat.z.ai/' },
        { name => 'WebMotors',        url => 'https://www.webmotors.com.br/' },
        { name => 'Panini Brasil',    url => 'https://panini.com.br/' },
        { name => 'RoboCore',         url => 'https://www.robocore.net/' },
        { name => 'Imperio Pizzaria', url => 'https://menu.beefood.com.br/imperiopizzaria/' },
        { name => 'Baroni Burguer',   url => 'https://baroniburger.mandarpedido.com/' },
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

sub ensure_skills {
    my $installer = File::Spec->catfile(
        $repo_root, File::Spec->updir, File::Spec->updir, 'Skill-Library', 'install.pl',
    );
    $installer = abs_path($installer) // $installer;

    unless (-f $installer) {
        say "SKIP    Skill-Library/install.pl not found ($installer)";
        return;
    }

    run_command($^X, $installer);
}

# Keep source checkouts outside the installed plugins: replacing runtime files
# must not lose the installer, and the dotfiles checkout can still be removed.
sub plugin_source {
    my ($name, $url) = @_;
    my $dir = File::Spec->catdir($target, '.local', 'share', 'dotfiles', 'sources', $name);
    if (-d File::Spec->catdir($dir, '.git')) {
        run_command('git', '-C', $dir, 'pull', '--ff-only');
    } else {
        die "Unmanaged source directory: $dir\n" if -e $dir;
        run_command('git', 'clone', '--depth', '1', $url, $dir);
    }
    return $dir;
}

sub ensure_omastore {
    my $source = plugin_source('OmaStore', 'https://github.com/KitsuneForgering/OmaStore.git');
    # The maintained installer verifies the release checksum and installs into
    # ~/.local. Skill-Library already owns this profile's agent skills.
    run_command('sh', File::Spec->catfile($source, 'packaging', 'install.sh'), '--no-skills');
    $ENV{PATH} = File::Spec->catdir($target, '.local', 'bin') . ':' . ($ENV{PATH} // '');
}

sub backup_plugin {
    my ($id) = @_;
    my $dir = File::Spec->catdir($target, '.config', 'omarchy', 'plugins', $id);
    return unless -e $dir || -l $dir;
    $plugin_backup_root //= $dry_run
        ? File::Spec->catdir($target, '.local', 'state', 'dotfiles', 'plugin-backups', $stamp)
        : reserve_backup_root(File::Spec->catdir($target, '.local', 'state', 'dotfiles', 'plugin-backups'));
    my $dest = File::Spec->catdir($plugin_backup_root, $id);
    run_command('mkdir', '-p', dirname($dest));
    run_command('cp', '-a', $dir, $dest);
}

sub replace_plugin {
    my ($id, $source) = @_;
    my $dir = File::Spec->catdir($target, '.config', 'omarchy', 'plugins', $id);
    my $stage = "$dir.dotfiles-tmp-$$";
    die "Staging path already exists: $stage\n" if -e $stage || -l $stage;
    run_command('omarchy', 'plugin', 'validate', $source);
    run_command('cp', '-a', $source, $stage);
    unless ($dry_run) {
        if (-e $dir || -l $dir) {
            $plugin_backup_root //= reserve_backup_root(File::Spec->catdir($target, '.local', 'state', 'dotfiles', 'plugin-backups'));
            my $old = File::Spec->catdir($plugin_backup_root, $id);
            make_path(dirname($old));
            move($dir, $old) or die "Cannot preserve $dir: $!\n";
            unless (rename $stage, $dir) {
                my $error = $!;
                move($old, $dir) or die "Cannot restore $dir from $old: $!\n";
                die "Cannot install $dir: $error\n";
            }
        } else {
            rename $stage, $dir or die "Cannot install $dir: $!\n";
        }
    }
}

sub command_output {
    my (@command) = @_;
    open my $fh, '-|', @command or die "Cannot run @command: $!\n";
    local $/;
    my $result = <$fh> // '';
    close $fh or die "Command failed: @command\n";
    return $result;
}

sub store_app {
    my ($repo) = @_;
    my $store = File::Spec->catfile($target, '.local', 'bin', 'omastore');
    run_command($store, 'index', '--force', $repo);
    run_command($store, 'install', $repo);
    run_command($store, 'deps', '--install', $repo);
    return if $dry_run;
    my $detail = decode_json(command_output($store, 'show', '--json', $repo));
    my $exec = $detail->{Install}{ExecPath};
    die "OmaStore did not install an executable for $repo\n" unless defined $exec && -x $exec;
    return $exec;
}

sub ensure_plugin {
    ensure_repo_packages('go');
    run_command('mkdir', '-p', File::Spec->catdir($target, '.config', 'omarchy', 'plugins'));
    my $feader = plugin_source('Feader-RSS', 'https://github.com/KitsuneForgering/Feader-RSS.git');
    backup_plugin('io.github.kitsunesemcalda.feader-rss');
    # Always rebuild when replacing the QML, so its protocol matches the backend.
    run_command('bash', File::Spec->catfile($feader, 'scripts', 'install.sh'));
    my $backend = File::Spec->catfile($target, '.config', 'omarchy', 'plugins',
        'io.github.kitsunesemcalda.feader-rss', 'feader-rss-fetch');
    die "Feader RSS backend missing: $backend\n" unless $dry_run || -x $backend;

    my $spaces = plugin_source('Spaces', 'https://github.com/tornikegomareli/omarchy-spaces.git');
    replace_plugin('tornikegomareli.spaces', $spaces);
    my $glass = plugin_source('Liquid-Glass', 'https://github.com/fasi96/omarchy-liquid-glass.git');
    replace_plugin('io.github.fasi96.liquid-glass', $glass);
    # Its installer preserves state.json and looks.json and generates the Lua
    # and terminal settings from them. These saved files are part of home/.
    run_command('bash', File::Spec->catfile($glass, 'install.sh'), '--yes',
        '--replace-hyprglass', '--hyprpm-update');

    my $vm_exec = store_app('KitsuneForgering/OmaVM');
    unless ($dry_run) {
        my $bin = File::Spec->catdir($target, '.local', 'bin');
        my $cli = File::Spec->catfile(dirname($vm_exec), 'omavm');
        die "OmaVM CLI missing: $cli\n" unless -x $cli;
        my $launcher = File::Spec->catfile($bin, 'omavm');
        if (-e $launcher || -l $launcher) {
            $plugin_backup_root //= reserve_backup_root(File::Spec->catdir($target, '.local', 'state', 'dotfiles', 'plugin-backups'));
            run_command('cp', '-a', $launcher, File::Spec->catfile($plugin_backup_root, 'omavm-cli'));
        }
        # A wrapper preserves the release's sibling bin/data layout and keeps
        # the checksum-verified binary owned by OmaStore.
        my $staged = "$launcher.dotfiles-tmp-$$";
        die "Staging path already exists: $staged\n" if -e $staged || -l $staged;
        open my $fh, '>', $staged or die "Cannot write $staged: $!\n";
        print {$fh} "#!/bin/sh\nexec " . shell_quote($cli) . ' "$@"' . "\n";
        close $fh or die "Cannot close $staged: $!\n";
        chmod 0755, $staged or die "Cannot chmod $staged: $!\n";
        rename $staged, $launcher or die "Cannot replace $launcher: $!\n";
    }
    my $vm = plugin_source('OmaVM', 'https://github.com/KitsuneForgering/OmaVM.git');
    replace_plugin('dev.omavm.bar', File::Spec->catdir($vm, 'contrib', 'dev.omavm.bar'));

    my $ai_exec = store_app('omribenami/Omarchy-AI');
    my $ai = $dry_run ? '<Omarchy-AI-release>' : dirname(dirname($ai_exec));
    for my $id (qw(settings watchdog assistant-huds chat-hud window-labels myapi tv-discovery quota-alert)) {
        replace_plugin("omarchy-ai.$id", File::Spec->catdir($ai, 'quickshell', 'plugins', "omarchy-ai.$id"));
    }
    # OmaStore only extracts the release. The full upstream installer provides
    # dependencies, the venv, systemd unit and all eight rendered QML plugins.
    run_command('bash', File::Spec->catfile($ai, 'install.sh'));
    run_command('systemctl', '--user', 'enable', '--now', 'omarchy-ai.service');
    run_command('systemctl', '--user', 'restart', 'omarchy-ai.service');

    run_command('omarchy-shell', 'shell', 'rescanPlugins');
    run_command('omarchy', 'plugin', 'disable', 'omarchy.workspaces');
    run_command('omarchy', 'plugin', 'enable', 'tornikegomareli.spaces', 'left');
    for my $id ('io.github.fasi96.liquid-glass', 'io.github.kitsunesemcalda.feader-rss', 'dev.omavm.bar') {
        run_command('omarchy', 'plugin', 'enable', $id, 'right');
    }
    run_command('omarchy', 'restart', 'shell');
    unless ($dry_run) {
        my $catalog = decode_json(command_output('omarchy', 'plugin', 'list', '--json'));
        my %enabled = map { $_->{id} => $_->{enabled} } @$catalog;
        for my $id ('tornikegomareli.spaces', 'io.github.fasi96.liquid-glass',
            'io.github.kitsunesemcalda.feader-rss', 'dev.omavm.bar',
            map { "omarchy-ai.$_" } qw(settings watchdog assistant-huds chat-hud window-labels myapi tv-discovery quota-alert)) {
            die "Plugin was not enabled: $id\n" unless $enabled{$id};
        }
    }
}

sub ensure_openrgb {
    # The build and the launcher point back into this checkout, so it has to
    # outlive the dotfiles clone.
    my $url = 'https://github.com/KitsuneSemCalda/Dareu-EK75-OpenRGB-Compat.git';
    my $dir = File::Spec->catdir($target, '.local', 'share', 'dareu-ek75-openrgb');

    if (-d File::Spec->catdir($dir, '.git')) {
        run_command('git', '-C', $dir, 'pull', '--ff-only');
    } else {
        run_command('git', 'clone', $url, $dir);
    }

    # Installs the udev rule (sudo), builds OpenRGB with the driver, and sets
    # up the launcher and the theme hook.
    run_command('bash', File::Spec->catfile($dir, 'install.sh'));
}

sub ensure_theme {
    my $url = 'https://github.com/KitsuneSemCalda/Sword-Art-Omarchy';
    my $dir = File::Spec->catdir($target, '.config', 'omarchy', 'themes', 'sword-art-omarchy');

    # A previous local checkout may have left a dangling symlink. Preserve it
    # before the official installer clones the theme into the same path.
    if (-l $dir && !-e $dir) {
        $backup_root //= $dry_run
            ? File::Spec->catdir($backup_base, $stamp)
            : reserve_backup_root();
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
  --plugin, --plugins replaces/enables all 12 desktop plugins and their backends
  --omastore         installs/reinstalls OmaStore (also implied by --plugin)
  --reboot           reboots after successful installation and Hyprland validation
  --theme            installs/applies the Sword Art Omarchy theme
  --openrgb          installs the Dareu EK75 OpenRGB driver, udev rule and theme hook
  --all              runs --apps --fonts --plugin --omastore --theme --openrgb
  --target PATH      uses a different root directory only to test file installation
  --help             shows this help
USAGE
    exit $status;
}
