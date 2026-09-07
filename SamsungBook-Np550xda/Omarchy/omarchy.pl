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
    die "--restore não pode ser combinado com --backup, --apps, --fonts, --plugin, --theme ou --all\n";
}

die "HOME não está definido; use --target CAMINHO\n"
    unless defined $target && length $target;

my $script_dir  = dirname(__FILE__);
$script_dir     = File::Spec->rel2abs($script_dir) unless File::Spec->file_name_is_absolute($script_dir);
my $repo_root   = $script_dir;
die "Não foi possível localizar o repositório\n" unless -d $repo_root;
my $source_root = File::Spec->catdir($repo_root, 'home');
$target         = abs_path($target) // File::Spec->rel2abs($target);

die "Diretório de origem ausente: $source_root\n" unless -d $source_root;
die "Destino ausente: $target\n" unless -d $target;

my $home_root = abs_path($ENV{HOME} // '') // '';
if (($apps || $fonts || $plugin || $theme) && $target ne $home_root) {
    die "Ações do Omarchy só podem usar o HOME real; use --target apenas para testar symlinks\n";
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
            warn "CONFLITO $relative (é um diretório; não será movido automaticamente)\n";
            $failures++;
            next;
        }
        unless ($backup) {
            warn "CONFLITO $relative (use --backup para preservar o original)\n";
            $failures++;
            next;
        }

        my $backup_path = File::Spec->catfile($backup_root, $relative);
        say "BACKUP  $relative -> " . File::Spec->abs2rel($backup_path, $target);
        make_path(dirname($backup_path)) unless $dry_run || -d dirname($backup_path);
        move($destination, $backup_path) unless $dry_run;
        die "Falha ao mover $destination para $backup_path: $!\n"
            unless $dry_run || -e $backup_path || -l $backup_path;
    }

    say(($dry_run ? 'LINK?   ' : 'LINK    ') . "$relative -> $source");
    next if $dry_run;

    make_path($parent) unless -d $parent;
    symlink($source, $destination)
        or die "Falha ao criar symlink $destination: $!\n";
}

die "$failures conflito(s) encontrado(s); nada conflitante foi sobrescrito\n" if $failures;

ensure_fonts()  if $fonts;
ensure_apps()   if $apps;
ensure_plugin() if $plugin;
ensure_theme()  if $theme;

say $dry_run ? 'Dry-run concluído.' : 'Dotfiles instalados.';
exit 0;

sub restore_backups {
    my ($backup_base) = @_;

    opendir my $backup_dir, $backup_base
        or die "Diretório de backups ausente: $backup_base\n";

    my @snapshots = sort grep {
        /^\d{8}-\d{6}$/ && -d File::Spec->catdir($backup_base, $_)
    } readdir $backup_dir;
    closedir $backup_dir;

    my $snapshot_name = $snapshots[-1]
        or die "Nenhum backup encontrado em $backup_base\n";
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

    die "Backup $snapshot_name não contém arquivos restauráveis\n"
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
        warn "CONFLITO $_ (o destino não é um symlink deste dotfiles)\n"
            for @conflicts;
        die scalar(@conflicts) . " conflito(s); restauração abortada sem alterar arquivos\n";
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
        ? 'Dry-run de restauração concluído.'
        : "Backup restaurado; cópia preservada em $snapshot";
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
        die "Não foi possível ler o symlink de backup $backup_path\n"
            unless defined $link;
        symlink($link, $destination)
            or die "Falha ao restaurar symlink $destination: $!\n";
        return;
    }

    copy($backup_path, $destination)
        or die "Falha ao copiar $backup_path para $destination: $!\n";
}

sub ensure_fonts {
    ensure_lexend_font();

    if (font_present('Lexend')) {
        say 'FONT    Lexend disponível';
    } elsif ($dry_run) {
        say 'FONT?   Lexend será usada após o download dos arquivos';
    } else {
        die "Lexend não foi encontrada após o download dos arquivos\n";
    }
}

sub ensure_lexend_font {
    my $font_dir = File::Spec->catdir($target, '.local', 'share', 'fonts', 'lexend');
    my %weight_of_file = (
        'Lexend-Regular.ttf' => 400,
        'Lexend-Bold.ttf'    => 700,
    );

    if (!grep { !-f File::Spec->catfile($font_dir, $_) } keys %weight_of_file) {
        say 'OK      arquivos da fonte Lexend já baixados';
        return;
    }

    if ($dry_run) {
        say 'FONT?   Lexend seria baixada do Google Fonts em ' . $font_dir;
        return;
    }

    make_path($font_dir) unless -d $font_dir;

    # Um user-agent genérico faz a API do Google Fonts responder com TrueType
    # (em vez de woff2), que é o formato que o fontconfig/Linux espera.
    my $css = qx{curl -sL -A 'Mozilla/5.0' 'https://fonts.googleapis.com/css2?family=Lexend:wght\@400;700'};
    die "Não foi possível obter o CSS do Google Fonts para Lexend\n" unless $css;

    my %url_of_weight;
    while ($css =~ /font-weight:\s*(\d+);\s*\n\s*src:\s*url\(([^)]+)\)/g) {
        $url_of_weight{$1} = $2;
    }

    for my $file (sort keys %weight_of_file) {
        my $weight = $weight_of_file{$file};
        my $url    = $url_of_weight{$weight}
            or die "URL da fonte Lexend (peso $weight) não encontrada no CSS do Google Fonts\n";
        run_command('curl', '-sL', $url, '-o', File::Spec->catfile($font_dir, $file));
    }

    run_command('fc-cache', '-f', $font_dir);
}

sub ensure_apps {
    for my $name ('HEY', 'Basecamp') {
        if (webapp_present($name)) {
            run_command('omarchy', 'webapp', 'remove', $name);
        } else {
            say "SKIP    web app $name não está instalado";
        }
    }

    my $onepassword_extension = '/usr/share/chromium/extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa.json';
    if (package_present('1password') || package_present('1password-cli') || -e $onepassword_extension) {
        run_command('omarchy', 'remove', 'service', '1password');
    } else {
        say 'SKIP    1Password não está instalado';
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
    );

    for my $app (@webapps) {
        if (webapp_present($app->{name})) {
            say "OK      web app $app->{name}";
            next;
        }

        # O argumento vazio faz o instalador oficial buscar o ícone do site.
        run_command('omarchy', 'webapp', 'install', $app->{name}, $app->{url}, '');
    }
}

sub ensure_plugin {
    my $id  = 'io.github.kitsunesemcalda.feader-rss';
    my $url = 'https://github.com/KitsuneSemCalda/Feader-RSS.git';
    my $dir = File::Spec->catdir($target, '.config', 'omarchy', 'plugins', $id);

    if (-d $dir) {
        say "OK      plugin $id já está instalado";
        run_command('omarchy', 'plugin', 'enable', $id, 'right');
    } else {
        # Sem --yes: o Omarchy mostra a confirmação de segurança para código
        # que será executado dentro do processo persistente do shell.
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
                or die "Falha ao preservar symlink de tema: $!\n";
        }
    }

    if (-d $dir) {
        say 'OK      tema Sword Art Omarchy já está instalado';
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
        say 'OK      pacotes oficiais já instalados: ' . join(', ', @packages);
    }
}

sub ensure_aur_packages {
    my @packages = @_;
    my @missing  = grep { !package_present($_) } @packages;
    if (@missing) {
        run_command('omarchy', 'pkg', 'aur', 'add', @missing);
    } else {
        say 'OK      pacotes AUR já instalados: ' . join(', ', @packages);
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
    open STDERR, '>&', $saved_stderr or die "Não foi possível restaurar stderr\n";
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
    die "Comando falhou ($status): $display\n" if $status == -1 || $status != 0;
}

sub shell_quote {
    my ($value) = @_;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub usage {
    my ($status) = @_;
    print <<'USAGE';
Uso: perl omarchy.pl [opções]

  --dry-run          mostra as ações sem criar links ou executar comandos
  --backup           move conflitos para ~/.local/state/dotfiles/backups/
  --restore          restaura o backup mais recente sem apagar a cópia
  --apps             remove itens antigos e instala apps/web apps pedidos
  --fonts            instala Lexend e ativa o perfil de fontes
  --plugin           instala/habilita o Feader-RSS
  --theme            instala/aplica o tema Sword Art Omarchy
  --all              executa --apps --fonts --plugin --theme
  --target CAMINHO   usa outro diretório-raiz apenas para testar symlinks
  --help             mostra esta ajuda
USAGE
    exit $status;
}
