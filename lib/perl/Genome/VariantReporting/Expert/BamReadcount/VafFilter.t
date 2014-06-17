#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::Exception;
use Test::More;
use Genome::VariantReporting::Expert::BamReadcount::TestHelper qw(bam_readcount_line create_entry);

my $pkg = "Genome::VariantReporting::Expert::BamReadcount::VafFilter";
use_ok($pkg);
my $factory = Genome::VariantReporting::Factory->create();
isa_ok($factory->get_class('filters', $pkg->name), $pkg);

subtest "__errors__ missing parameters" => sub {
    my $filter = $pkg->create(sample_name => "S1");
    my @errors = $filter->__errors__;
    is(scalar(@errors), 1, "One error found");
    like($errors[0]->desc, qr/Must define at least one of min_vaf or max_vaf/, "Error message as expected");
};

subtest "__errors__ invalid parameters" => sub {
    my $filter = $pkg->create(min_vaf => 100, max_vaf => 90, sample_name => "S1");
    my @errors = $filter->__errors__;
    is(scalar(@errors), 1, "One error found");
    like($errors[0]->desc, qr/Max_vaf must be larger or equal to min_vaf/, "Error message as expected");
};

subtest "pass min vaf" => sub {
    my $min_vaf = 90;
    my $filter = $pkg->create(min_vaf => $min_vaf, sample_name => "S1");
    lives_ok(sub {$filter->validate}, "Filter validates");

    my %expected_return_values = (
        G => 1,
        C => 0,
    );
    my $entry = create_entry(bam_readcount_line);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry passes filter with min_vaf $min_vaf");
};

subtest "pass max vaf" => sub {
    my $max_vaf = 100;
    my $filter = $pkg->create(max_vaf => $max_vaf, sample_name => "S1");
    lives_ok(sub {$filter->validate}, "Filter validates");

    my %expected_return_values = (
        G => 1,
        C => 0,
    );
    my $entry = create_entry(bam_readcount_line);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry passes filter with max_vaf $max_vaf");
};

subtest "pass min and max vaf" => sub {
    my $min_vaf = 90;
    my $max_vaf = 100;
    my $filter = $pkg->create(min_vaf => $min_vaf, max_vaf => $max_vaf, sample_name => "S1");
    lives_ok(sub {$filter->validate}, "Filter validates");

    my %expected_return_values = (
        G => 1,
        C => 0,
    );
    my $entry = create_entry(bam_readcount_line);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry passes filter with min_vaf $min_vaf and max_vaf $max_vaf");
};

subtest "fail min vaf" => sub {
    my $min_vaf = 100;
    my $filter = $pkg->create(min_vaf => $min_vaf, sample_name => "S1");
    lives_ok(sub {$filter->validate}, "Filter validates");

    my %expected_return_values = (
        G => 0,
        C => 0,
    );
    my $entry = create_entry(bam_readcount_line);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry fails filter with min_vaf $min_vaf");
};

subtest "fail max vaf" => sub {
    my $max_vaf = 90;
    my $filter = $pkg->create(max_vaf => $max_vaf, sample_name => "S1");
    lives_ok(sub {$filter->validate}, "Filter validates");

    my %expected_return_values = (
        G => 0,
        C => 0,
    );
    my $entry = create_entry(bam_readcount_line);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry fails filter with max_vaf $max_vaf");
};

subtest "fail heterozygous non-reference sample" => sub {
    my $min_vaf = 90;
    my $filter = $pkg->create(min_vaf => $min_vaf, sample_name => "S2");
    lives_ok(sub {$filter->validate}, "Filter validates");

    my %expected_return_values = (
        G => 1,
        C => 0,
    );
    my $entry = create_entry(bam_readcount_line);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry fails filter with min_vaf $min_vaf");
    cmp_ok(Genome::VariantReporting::Expert::BamReadcount::VafCalculator::calculate_vaf(
        $filter->get_readcount_entry($entry), 'C'), '<', 0.3, "VAF is very low");
    cmp_ok(Genome::VariantReporting::Expert::BamReadcount::VafCalculator::calculate_vaf(
        $filter->get_readcount_entry($entry), 'G'), '>', 90, "VAF is high");
};

subtest "pass heterozygous non-reference sample" => sub {
    my $min_vaf = 0.02;
    my $filter = $pkg->create(min_vaf => $min_vaf, sample_name => "S2");
    lives_ok(sub {$filter->validate}, "Filter validates");

    my %expected_return_values = (
        G => 1,
        C => 1,
    );
    my $entry = create_entry(bam_readcount_line);
    is_deeply({$filter->filter_entry($entry)}, \%expected_return_values, "Entry passes filter with min_vaf $min_vaf");
};

done_testing;
