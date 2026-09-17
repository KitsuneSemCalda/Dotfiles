#!/usr/bin/env perl
use 5.036;
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use Getopt::Long qw(GetOptions);

my %AGENTS = (
    claude   => File::Spec->catdir($ENV{HOME}, '.claude', 'skills'),
    codex    => File::Spec->catdir($ENV{HOME}, '.codex',  'skills'),
    opencode => File::Spec->catdir($ENV{HOME}, '.config', 'opencode', 'skills'),
);

my $only_agent = '';
my $dry_run    = 0;
my $list       = 0;
my $help       = 0;

GetOptions(
    'agent=s' => \$only_agent,
    'dry-run' => \$dry_run,
    'list'    => \$list,
    'help'    => \$help,
) or usage(2);

usage(0) if $help;

my $script_dir = abs_path(dirname(__FILE__)) or die "Could not locate the script\n";
my $skills_dir = File::Spec->catdir($script_dir, 'skills');

my @skills = list_skills($skills_dir);

if ($list) {
    say 'Skills in the library:';
    if (@skills) {
        say "  - $_" for @skills;
    }
    else {
        say '  (none yet)';
    }
    say '';
    say 'Agents detected on this machine:';
    for my $agent (sort keys %AGENTS) {
        my $dest      = $AGENTS{$agent};
        my $installed = -d dirname($dest);
        say '  - ' . $agent . ' -> ' . $dest . ($installed ? '' : ' (not installed, skipped)');
    }
    exit 0;
}

if (!@skills) {
    say 'No skills found under Skill-Library/skills — nothing to install.';
    exit 0;
}

my @agent_names = $only_agent ? ($only_agent) : sort keys %AGENTS;
for my $agent (@agent_names) {
    die "Unknown agent '$agent'. Known agents: " . join(', ', sort keys %AGENTS) . "\n"
        unless exists $AGENTS{$agent};
}

my @targets = grep { -d dirname($AGENTS{$_}) } @agent_names;

if (!@targets) {
    say 'No supported agent CLI detected on this machine (looked for ~/.claude, ~/.codex and ~/.config/opencode). Nothing installed.';
    exit 0;
}

for my $agent (@targets) {
    my $target = $AGENTS{$agent};
    for my $skill (@skills) {
        my $src  = File::Spec->catdir($skills_dir, $skill);
        my $dest = File::Spec->catdir($target, $skill);
        if ($dry_run) {
            say "Would install $skill -> $dest";
            next;
        }
        copy_tree($src, $dest);
        say "Installed $skill -> $dest";
    }
}

sub list_skills {
    my ($dir) = @_;
    return () unless -d $dir;
    opendir my $dh, $dir or die "Could not read $dir: $!\n";
    my @names = sort grep { !/^\./ && -f File::Spec->catfile($dir, $_, 'SKILL.md') } readdir $dh;
    closedir $dh;
    return @names;
}

sub copy_tree {
    my ($src, $dest) = @_;
    make_path($dest);
    opendir my $dh, $src or die "Could not read $src: $!\n";
    for my $entry (readdir $dh) {
        next if $entry eq '.' || $entry eq '..';
        my $src_path  = File::Spec->catfile($src,  $entry);
        my $dest_path = File::Spec->catfile($dest, $entry);
        if (-d $src_path) {
            copy_tree($src_path, $dest_path);
        }
        else {
            copy($src_path, $dest_path) or die "Could not copy $src_path to $dest_path: $!\n";
        }
    }
    closedir $dh;
}

sub usage {
    my ($status) = @_;
    print <<'USAGE';
Usage: perl Skill-Library/install.pl [options]

  --agent <name>  installs into only one agent (claude, codex, opencode)
  --list          lists the skills in the library and the agents detected
  --dry-run       shows what would be installed without copying anything
  --help          shows this help

With no options, every skill under skills/ is copied into the skills
directory of every supported agent CLI detected on this machine.
USAGE
    exit $status;
}
