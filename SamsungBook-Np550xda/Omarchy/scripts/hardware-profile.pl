#!/usr/bin/env perl
use 5.036;
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec;
use Getopt::Long qw(GetOptions);
use POSIX qw(strftime);

my $save  = 0;
my $print = 0;
my $help  = 0;

GetOptions(
    'save'  => \$save,
    'print' => \$print,
    'help'  => \$help,
) or usage(2);

usage(0) if $help;

my $script_dir = abs_path(dirname(__FILE__)) or die "Não foi possível localizar o script\n";
my $repo_root  = abs_path(File::Spec->catdir($script_dir, File::Spec->updir))
    or die "Não foi possível localizar o repositório\n";
my $output = File::Spec->catfile($repo_root, 'hardware', 'inxi-Fz.txt');

open my $pipe, '-|', 'inxi', '-Fz', '--color', '0'
    or die "Não foi possível executar inxi: $!\n";
local $/;
my $report = <$pipe> // '';
close $pipe or die "inxi terminou com erro\n";

if ($print || !$save) {
    print $report;
    exit 0;
}
open my $file, '>', $output or die "Não foi possível escrever $output: $!\n";
print {$file} '# Snapshot gerado por `inxi -Fz` em '
    . strftime('%Y-%m-%d %H:%M:%S %z', localtime) . "\n\n";
print {$file} $report;
close $file or die "Não foi possível fechar $output: $!\n";
say "Snapshot salvo em $output";

sub usage {
    my ($status) = @_;
    print <<'USAGE';
Uso: perl scripts/hardware-profile.pl [opções]

  --save    atualiza hardware/inxi-Fz.txt
  --print   imprime o relatório (comportamento padrão)
  --help    mostra esta ajuda
USAGE
    exit $status;
}
