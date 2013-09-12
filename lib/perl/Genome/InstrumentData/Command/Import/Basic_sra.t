#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above "Genome";

require File::Compare;
require Genome::Utility::Test;
use Test::More;

use_ok('Genome::InstrumentData::Command::Import::Basic') or die;

my $test_dir = Genome::Utility::Test->data_dir_ok('Genome::InstrumentData::Command::Import');
my $source_sra = $test_dir.'/input.sra';
ok(-s $source_sra, 'source sra exists') or die;

my $sample = Genome::Sample->create(name => '__TEST_SAMPLE__');
ok($sample, 'Create sample');

my $cmd = Genome::InstrumentData::Command::Import::Basic->create(
    sample => $sample,
    source_files => [$source_sra],
    import_source_name => 'sra',
    instrument_data_properties => [qw/ lane=2 flow_cell_id=XXXXXX /],
);
ok($cmd, "create import command");
ok($cmd->execute, "excute import command") or die;

my $instrument_data = Genome::InstrumentData::Imported->get(original_data_path => $source_sra);
ok($instrument_data, 'got instrument data');
is($instrument_data->original_data_path, $source_sra, 'original_data_path correctly set');
is($instrument_data->import_format, 'bam', 'import_format is bam');
is($instrument_data->sequencing_platform, 'solexa', 'sequencing_platform correctly set');
is($instrument_data->is_paired_end, 0, 'is_paired_end correctly set');
is($instrument_data->read_count, 148, 'read_count correctly set');
my $allocation = $instrument_data->allocations;
ok($allocation, 'got allocation');
ok($allocation->kilobytes_requested > 0, 'allocation kb was set');

# sra
#ok(-s $allocation->absolute_path.'/all_sequences.sra', 'sra file was copied');
#ok(-s $allocation->absolute_path.'/all_sequences.sra.dbcc', 'dbcc file exists');

my $bam_path = $instrument_data->bam_path;
ok(-s $bam_path, 'bam path exists');
is($bam_path, $instrument_data->data_directory.'/all_sequences.bam', 'bam path correctly named');
is(eval{$instrument_data->attributes(attribute_label => 'bam_path')->attribute_value}, $bam_path, 'set attributes bam path');
is(File::Compare::compare($bam_path, $test_dir.'/input.sra.sorted.bam'), 0, 'sra dumped and sorted bam matches');
is(File::Compare::compare($bam_path.'.flagstat', $test_dir.'/input.sra.sorted.bam.flagstat'), 0, 'flagstat matches');

#print $instrument_data->data_directory."\n"; <STDIN>;
done_testing();
