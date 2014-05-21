#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Utility::Test;
use Genome::Test::Factory::InstrumentData::MergedAlignmentResult;
use Genome::Test::Factory::InstrumentData::Imported;
use Genome::Test::Factory::Model::GenotypeMicroarray;
use Genome::Test::Factory::Build;

my $package = "Genome::InstrumentData::VerifyBamIdResult";

use_ok($package);

my $test_dir = Genome::Utility::Test->data_dir_ok($package, "v2");

my ($instrument_data_1, $sample, $dbsnp_build, $on_target_feature_list) = setup_objects($test_dir);

subtest test_convert_caf_to_af => sub {
    is(Genome::InstrumentData::VerifyBamIdResult::_convert_caf_to_af(create_entry("[0.07163,0.9284]")), "0.9284");
};

subtest test_on_target => sub{
    my $sr = Genome::InstrumentData::VerifyBamIdResult->create(
        sample => $sample,
        known_sites_build => $dbsnp_build,
        genotype_filters => ["chromosome:exclude=X,Y,MT"],
        aligned_bam_result => $instrument_data_1,
        on_target_list => $on_target_feature_list,
        max_depth => 20,
        precise => 0,
        version => "20120620",
        result_version => 2,
    );
    ok($sr, "Software result was created ok");
    test_metrics($sr);
};

subtest test_no_intersect => sub{
    my $sr = Genome::InstrumentData::VerifyBamIdResult->create(
        sample => $sample,
        known_sites_build => $dbsnp_build,
        genotype_filters => ["chromosome:exclude=X,Y,MT"],
        aligned_bam_result => $instrument_data_1,
        max_depth => 20,
        precise => 0,
        version => "20120620",
        result_version => 2,
    );
    ok($sr, "Software result was created ok");
    test_metrics($sr);
};

done_testing;

sub test_metrics {
    my $result = shift;
    ok(defined $result->freemix, "Freemix is defined");
    ok($result->freemix ne "NA", "Freemix is not NA");
    ok(defined $result->chipmix, "Chipmix is defined");
    ok(defined $result->af_count, "af_count is defined");
    ok($result->af_count > 0, "af_count is > 0");
}

sub setup_objects {
    my $test_dir = shift;
    my $bam_result_1 = Genome::Test::Factory::InstrumentData::MergedAlignmentResult->setup_object(
        bam_path => File::Spec->join($test_dir, "1.bam"));

    my $model = Genome::Test::Factory::Model::GenotypeMicroarray->setup_object();

    my $tmp_dir = Genome::Sys->create_temp_directory;
    Genome::Sys->copy_file(File::Spec->join($test_dir,"1.vcf"), 
        File::Spec->join($tmp_dir, "snvs.hq.vcf"));
    my $dbsnp_result = Genome::Model::Tools::DetectVariants2::Result::Manual->__define__(output_dir => $tmp_dir);

    my $genotype_data = Genome::Test::Factory::InstrumentData::Imported->setup_object(genotype_file => File::Spec->join($test_dir, "1.genotype"));

    my $build = Genome::Test::Factory::Build->setup_object(
        instrument_data => [$genotype_data],
        model_id => $model->id,
    );
    $build->dbsnp_build->reference->add_input(name => "allosome_names", value_class_name => "UR::Value", value_id => "X,Y,MT");
    $build->dbsnp_build->version("fake");
    $build->dbsnp_build->snv_result($dbsnp_result);

    my $vcf_result = Genome::InstrumentData::Microarray::Result::Vcf->__define__(
        sample => $genotype_data->sample,
        known_sites_build => $build->dbsnp_build,
        output_dir => $test_dir,
    );
    Genome::SoftwareResult::Input->create(
        software_result => $vcf_result,
        name => "filters-0",
        value_id => "chromosome:exclude=X,Y,MT",
    );
    $vcf_result->lookup_hash($vcf_result->calculate_lookup_hash);

    my $on_target_bed = File::Spec->join($test_dir, "on_target.bed");
    my $on_target_feature_list = Genome::FeatureList->create(
        file_path => $on_target_bed,
        file_content_hash => Genome::Sys->md5sum($on_target_bed),
    );
    return ($bam_result_1, $genotype_data->sample, $build->dbsnp_build, $on_target_feature_list);
}

sub create_vcf_header {
    my $header_txt = <<EOS;
##fileformat=VCFv4.1
##INFO=<ID=CAF,Number=.,Type=Float,Description="Info field A">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO
EOS
    my @lines = split("\n", $header_txt);
    my $header = Genome::File::Vcf::Header->create(lines => \@lines);
    return $header
}

sub create_entry {
    my $caf = shift;
    my @fields = (
        '1',            # CHROM
        10,             # POS
        '.',            # ID
        'A',            # REF
        'C',            # ALT
        '10.3',         # QUAL
        '.',         # FILTER
    );

    if ($caf) {
        push @fields, "CAF=$caf";
    }

    my $entry_txt = join("\t", @fields);
    my $entry = Genome::File::Vcf::Entry->new(create_vcf_header(), $entry_txt);
    return $entry;
}
