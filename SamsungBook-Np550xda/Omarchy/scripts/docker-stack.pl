#!/usr/bin/env perl
use 5.036;
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptions);

my $up          = 0;
my $down        = 0;
my $status      = 0;
my $dns         = 0;
my $dns_revert  = 0;
my $agents      = 0;
my $dry_run     = 0;
my $notes_dir   = File::Spec->catdir($ENV{HOME} // '', 'Documents', 'notes');
my $help        = 0;

GetOptions(
    'up'          => \$up,
    'down'        => \$down,
    'status'      => \$status,
    'dns'         => \$dns,
    'dns-revert'  => \$dns_revert,
    'agents'      => \$agents,
    'notes-dir=s' => \$notes_dir,
    'dry-run'     => \$dry_run,
    'help'        => \$help,
) or usage(2);

usage(0) if $help;

if ($dns && $dns_revert) {
    die "--dns cannot be combined with --dns-revert\n";
}

unless ($up || $down || $status || $dns || $dns_revert || $agents) {
    usage(1);
}

# Each locally supported agent CLI mapped to the --client / --agent name
# expected by ai-memory (not always the same as the binary name).
my %client_of_binary = (
    claude         => 'claude-code',
    codex          => 'codex',
    gemini         => 'gemini-cli',
    'cursor-agent' => 'cursor',
    opencode       => 'opencode',
    grok           => 'grok',
);

my $script_dir = abs_path(dirname(__FILE__)) or die "Could not locate the script\n";
my $repo_root  = abs_path(File::Spec->catdir($script_dir, File::Spec->updir))
    or die "Could not locate the repository\n";
my $docker_dir = File::Spec->catdir($repo_root, 'docker');
my $env_file   = File::Spec->catfile($docker_dir, '.env');

die "Missing docker/ directory at $docker_dir\n" unless -d $docker_dir;

if ($up) {
    my $notes_abs = File::Spec->rel2abs($notes_dir);
    ensure_notes_dir($notes_abs);
    ensure_env($notes_abs);
    compose('up', '-d');
}

compose('down')  if $down;
compose('ps')    if $status;
cmd_agents()     if $agents;
cmd_dns()        if $dns;
cmd_dns_revert() if $dns_revert;

exit 0;

sub ensure_notes_dir {
    my ($dir) = @_;
    if (-d $dir) {
        say "OK      $dir already exists";
        return;
    }
    say(($dry_run ? 'DIR?    ' : 'DIR     ') . $dir);
    make_path($dir) unless $dry_run;
}

sub ensure_env {
    my ($notes_abs) = @_;
    if (-e $env_file) {
        say "OK      $env_file already exists (secrets are not regenerated)";
        return;
    }
    if ($dry_run) {
        say "ENV?    $env_file would be created with generated secrets";
        return;
    }

    my @pairs = (
        [POSTGRES_USER               => 'postgres'],
        [POSTGRES_PASSWORD           => random_hex(24)],
        [POSTGRES_DB                 => 'postgres'],
        [REDIS_PASSWORD              => random_hex(24)],
        [FRANKMD_NOTES_DIR           => $notes_abs],
        [FRANKMD_SECRET_KEY_BASE     => random_hex(64)],
        [FRANKMD_AUTH_TOKEN          => random_hex(24)],
        [TZ                          => 'America/Sao_Paulo'],
        [PIHOLE_PASSWORD             => random_hex(16)],
        [AI_MEMORY_LLM_PROVIDER      => ''],
        [ANTHROPIC_API_KEY           => ''],
        [AI_MEMORY_EMBEDDING_PROVIDER => ''],
        [OPENAI_API_KEY              => ''],
    );

    open my $file, '>', $env_file or die "Could not write $env_file: $!\n";
    say {$file} "$_->[0]=$_->[1]" for @pairs;
    close $file or die "Could not close $env_file: $!\n";
    chmod 0600, $env_file;
    say "ENV     $env_file created with generated secrets (permission 600)";
}

sub random_hex {
    my ($bytes) = @_;
    my $value = qx{openssl rand -hex $bytes};
    chomp $value;
    die "Could not generate a random secret (openssl missing?)\n" unless length $value;
    return $value;
}

sub compose {
    my (@args) = @_;
    run_command('docker', 'compose', '--project-directory', $docker_dir, '--env-file', $env_file, @args);
}

sub cmd_agents {
    my $wrapper = ensure_wrapper();
    my @detected = grep { binary_present($_) } sort keys %client_of_binary;

    unless (@detected) {
        say 'SKIP    no supported AI agent was found on PATH';
        return;
    }

    for my $binary (@detected) {
        my $client = $client_of_binary{$binary};
        say "AGENT   $binary -> $client";
        run_command($wrapper, 'install-mcp',   '--client', $client, '--apply');
        run_command($wrapper, 'install-hooks', '--agent',  $client, '--apply');
    }
}

sub ensure_wrapper {
    my $wrapper = File::Spec->catfile($ENV{HOME}, '.local', 'bin', 'ai-memory');
    return $wrapper if -x $wrapper;

    if ($dry_run) {
        say "WRAPPER? $wrapper would be downloaded and installed";
        return $wrapper;
    }

    make_path(dirname($wrapper));
    my $tmp  = tempdir(CLEANUP => 1);
    my $base = 'https://github.com/akitaonrails/ai-memory/releases/latest/download/ai-memory-wrapper';

    run_command('curl', '-fsSL', $base, '-o', "$tmp/ai-memory-wrapper");
    run_command('curl', '-fsSL', "$base.sha256", '-o', "$tmp/ai-memory-wrapper.sha256");

    my $expected = qx{awk 'NR==1{print \$1}' "$tmp/ai-memory-wrapper.sha256"};
    chomp $expected;
    my $actual = qx{sha256sum "$tmp/ai-memory-wrapper" | awk '{print \$1}'};
    chomp $actual;
    die "ai-memory wrapper checksum mismatch (expected $expected, got $actual)\n"
        unless length $expected && $expected eq $actual;

    run_command('install', '-m', '0755', "$tmp/ai-memory-wrapper", $wrapper);
    say "WRAPPER $wrapper installed";
    return $wrapper;
}

sub binary_present {
    my ($name) = @_;
    return system('command -v ' . shell_quote($name) . ' >/dev/null 2>&1') == 0;
}

sub cmd_dns {
    wait_pihole_healthy() unless $dry_run;

    # omarchy-dns already filters to real Wi-Fi/Ethernet connections, updates
    # NetworkManager and systemd-resolved together, and reloads the whole
    # stack — reimplementing this via nmcli directly already left Docker's
    # bridges unable to forward packets once (NM here also manages them).
    my $servers = '127.0.0.1 1.1.1.1';
    if ($dry_run) {
        say "RUN?    echo '$servers' | omarchy dns Custom";
        return;
    }
    say "RUN     echo '$servers' | omarchy dns Custom";
    open my $pipe, '|-', 'omarchy', 'dns', 'Custom'
        or die "Could not run omarchy dns Custom: $!\n";
    print {$pipe} "$servers\n";
    close $pipe;
    die "omarchy dns Custom failed\n" if $?;
    say 'DNS     Pi-hole (127.0.0.1, fallback 1.1.1.1) applied via omarchy dns Custom';
}

sub cmd_dns_revert {
    run_command('omarchy', 'dns', 'DHCP');
}

sub wait_pihole_healthy {
    for (1 .. 20) {
        my $health = qx{docker inspect --format '{{.State.Health.Status}}' omarchy-pihole 2>/dev/null};
        chomp $health;
        return if $health eq 'healthy';
        sleep 1;
    }
    die "Pi-hole did not become healthy in time; run --up and check "
        . "'docker logs omarchy-pihole' before trying --dns again\n";
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
Usage: perl scripts/docker-stack.pl [options]

  --up               creates docker/.env (if missing), the notes folder, and
                      brings up postgres, redis, frankmd, ai-memory, and pihole
  --down             tears down the stack's containers
  --status           shows the containers' state (docker compose ps)
  --agents           installs the ai-memory wrapper and wires up each AI CLI
                      detected on PATH (claude, codex, gemini, cursor-agent,
                      opencode, grok) via install-mcp/install-hooks
  --dns              points the system DNS to Pi-hole (127.0.0.1, with
                      fallback 1.1.1.1) via `omarchy dns Custom`; waits for
                      the container to become healthy before applying
  --dns-revert       runs `omarchy dns DHCP` (reverts to automatic DNS)
  --notes-dir PATH   uses a different FrankMD notes folder (default: ~/Documents/notes)
  --dry-run          shows the actions without running anything
  --help             shows this help
USAGE
    exit $status;
}
