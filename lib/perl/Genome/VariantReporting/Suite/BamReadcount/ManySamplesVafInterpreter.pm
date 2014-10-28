package Genome::VariantReporting::Suite::BamReadcount::ManySamplesVafInterpreter;

use strict;
use warnings;
use Genome;
use Genome::VariantReporting::Suite::BamReadcount::VafInterpreter;
use Genome::VariantReporting::Suite::BamReadcount::VafInterpreterHelpers qw(basic_available_fields basic_field_descriptions);

class Genome::VariantReporting::Suite::BamReadcount::ManySamplesVafInterpreter {
    is => ['Genome::VariantReporting::Framework::Component::Interpreter', 'Genome::VariantReporting::Framework::Component::WithManySampleNames'],
    has => [],
};

sub name {
    return 'many-samples-vaf';
}

sub requires_annotations {
    return ('bam-readcount');
}

sub field_descriptions {
    my $self = shift;

    my %field_descriptions;
    for my $sample_name ($self->sample_names) {
        my %field_descriptions_for_sample = basic_field_descriptions($sample_name);
        for my $field (basic_available_fields()) {
            my $sample_specific_field = $self->create_sample_specific_field_name($field, $sample_name);
            $field_descriptions{$sample_specific_field} = $field_descriptions_for_sample{$field};
        }
    }
    return %field_descriptions;
}

sub available_fields {
    my $self = shift;

    return $self->create_sample_specific_field_names([basic_available_fields()], [$self->sample_names]);
}

sub _interpret_entry {
    my $self = shift;
    my $entry = shift;
    my $passed_alt_alleles = shift;

    my %return_values;
    for my $sample_name ($self->sample_names) {
        my $interpreter = Genome::VariantReporting::Suite::BamReadcount::VafInterpreter->create(sample_name => $sample_name);
        my %result = $interpreter->interpret_entry($entry, $passed_alt_alleles);
        for my $alt_allele (@$passed_alt_alleles) {
            for my $vaf_field (basic_available_fields()) {
                my $sample_specific_field_name = $self->create_sample_specific_field_name($vaf_field, $sample_name);
                $return_values{$alt_allele}->{$sample_specific_field_name} = $result{$alt_allele}->{$vaf_field};
            }
        }
    }
    return %return_values;
}

1;
