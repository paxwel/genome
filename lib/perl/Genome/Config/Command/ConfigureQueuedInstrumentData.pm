package Genome::Config::Command::ConfigureQueuedInstrumentData;

use strict;
use warnings;

use Genome;

use Lingua::EN::Inflect;

class Genome::Config::Command::ConfigureQueuedInstrumentData {
    is => 'Command::V2',
    has => [
        instrument_data => {
            is          => 'Genome::InstrumentData',
            is_many     => 1,
            is_optional => 1,
            doc         => '[Re]process these instrument data.',
        },
        limit => {
            is => 'Integer',
            default => 50,
            doc => 'Maximum number of instrument data analysis project pairs to process in a single run'
        },
    ],
};

sub help_brief {
    return 'Assign instrument data with an analysis project to models';
}

sub help_synopsis {
    return <<EOS
EOS
}

sub help_detail {
    return <<EOS
EOS
}

sub execute {
    my $self = shift;

    $self->_lock();

    my @instrument_data_analysis_project_pairs = $self->_get_items_to_process();
    $self->status_message(sprintf('Found %s to process.',
            Lingua::EN::Inflect::NO('item', scalar(@instrument_data_analysis_project_pairs))));

    for my $current_pair (@instrument_data_analysis_project_pairs) {
        my $current_inst_data = $current_pair->instrument_data;
        my $analysis_project = $current_pair->analysis_project;
        eval {
            my $config = $analysis_project->get_configuration_reader();
            my $hashes = $self->_prepare_configuration_hashes_for_instrument_data($current_inst_data, $config);
            while (my ($model_type, $model_hashes) = (each %$hashes)) {
                if ($model_type->requires_pairing) {
                    $model_hashes = $self->_process_paired_samples($analysis_project, $current_inst_data, $model_hashes);
                }
                $self->_process_models($analysis_project, $current_inst_data, $model_type, $model_hashes);
            }
        };

        my $error = $@;
        $self->error_message($error) if $error;
        $self->_mark_sync_status($current_pair, $error);
    }

    return 1;
}

sub _process_models {
    my $self = shift;
    my $analysis_project = shift;
    my $instrument_data = shift;
    my $model_type = shift;
    my $model_list = shift;

    for my $model_instance (@$model_list) {
        my ($model, $created_new) = $self->_get_model_for_config_hash($model_type, $model_instance);

        $self->status_message(sprintf('Model: %s %s for instrument data: %s.',
                $model->id, ($created_new ? 'created' : 'found'), $instrument_data->id ));

        $self->_assign_instrument_data_to_model($model, $instrument_data, $created_new);
        $self->_assign_model_to_analysis_project($analysis_project, $model);
        $self->_update_models_for_associated_projects($instrument_data);
    }
}

sub _assign_instrument_data_to_model {
    my ($self, $model, $instrument_data, $newly_created) = @_;

    #if a model is newly created, we want to assign all applicable instrument data to it
    my %params_hash = (model => $model);
    if ($newly_created && $model->auto_assign_inst_data) {
        $params_hash{all} = 1;
    } else {
        $params_hash{instrument_data} = [$instrument_data];
    }

    my $cmd = Genome::Model::Command::InstrumentData::Assign->create(%params_hash);
    unless ($cmd->execute()) {
        die(sprintf('Failed to assign %s to %s', $instrument_data->__display_name__,
                $model->__display_name__));
    }

    $self->_request_build_if_necessary($model, $newly_created);
}

sub _request_build_if_necessary {
    my ($self, $model, $newly_created) = @_;

    my $reason = $newly_created? 'created' : 'processed';

    if($model->build_needed) {
        $model->build_requested(1, "CQID $reason model");
    }
}

sub _mark_sync_status {
    my ($self, $current_pair, $error) = @_;

    if ($error) {
        $self->_mark_pair_as_failed($current_pair, $error);
    } else {
        $self->_mark_pair_as_processed($current_pair);
    }

    return 1;
}

sub _mark_pair_as_processed {
    my ($self, $current_pair) = @_;

    $current_pair->fail_count(0);
    $current_pair->reason(undef);
    $current_pair->status('processed');

    return 1;
}

sub _mark_pair_as_failed {
    my ($self, $current_pair, $error_message) = @_;

    my $previous_count = $current_pair->fail_count;
    $current_pair->fail_count(++$previous_count);
    $current_pair->status('failed');
    $current_pair->reason($error_message);

    return 1;
}

sub _get_model_for_config_hash {
    my $self = shift;
    my $class_name = shift;
    my $config = shift;

    my %read_config = %$config;
    for my $key (keys %read_config) {
        my $value = $read_config{$key};
        if(ref($value) eq 'ARRAY' and scalar(@$value) == 0) {
            $read_config{$key} = undef;
        }
    }

    my @extra_params = (auto_assign_inst_data => 1);

    my @m = $class_name->get(@extra_params, %read_config);

    if (scalar(@m) > 1) {
        die(sprintf("Sorry, but multiple identical models were found: %s", join(',', map { $_->id } @m)));
    };
    #return the model, plus a 'boolean' value indicating if we created a new model
    push @extra_params, ( user_name => 'apipe-builder' );
    my @model_info =  $m[0] ? ($m[0], 0) : ($class_name->create(@extra_params, %$config), 1);
    return wantarray ? @model_info : $model_info[0];
}

sub _prepare_configuration_hashes_for_instrument_data {
    my ($self, $instrument_data, $config_obj) = @_;

    my $config_hash = $config_obj->get_config(
        sequencing_platform => $instrument_data->sequencing_platform,
        domain              => _normalize_domain($instrument_data->taxon->domain),
        taxon               => _normalize_taxon($instrument_data->species_name),
        type                => _normalize_extraction_type($instrument_data->sample->extraction_type),
    );

    for my $model_type (keys %$config_hash) {
        if (ref $config_hash->{$model_type} ne 'ARRAY') {
            $config_hash->{$model_type} = [$config_hash->{$model_type}];
        }

        for my $model_instance (@{$config_hash->{$model_type}}) {
            my $instrument_data_properties = delete $model_instance->{instrument_data_properties};
            if($instrument_data_properties) {
                while((my $model_property, my $instrument_data_property) = each %$instrument_data_properties) {
                    if (ref $instrument_data_property eq 'ARRAY') {
                        $model_instance->{$model_property} = [
                            grep { defined($_) }
                            map { $instrument_data->$_ }
                            @$instrument_data_property
                        ];
                    } else {
                        $model_instance->{$model_property} = $instrument_data->$instrument_data_property if defined($instrument_data->$instrument_data_property);
                    }
                }
            }
        }
    }
    return $config_hash;
}

sub _process_paired_samples {
    my ($self, $analysis_project, $instrument_data, $model_hashes) = @_;
    die('Must provide an analysis project, a piece of instrument data and a config hash!')
        unless($analysis_project && $instrument_data && $model_hashes);

    my @subject_pairings = Genome::Config::AnalysisProject::SubjectPairing->get(
        -or => [
            [ analysis_project => $analysis_project, control_subject => $instrument_data->sample],
            [ analysis_project => $analysis_project, experimental_subject => $instrument_data->sample]
        ],
    );

    unless (@subject_pairings) {
        die(sprintf('Found no pairing information for %s in project %s for a model type that requires pairing!',
            $instrument_data->__display_name__,
            $analysis_project->__display_name__));
    }

    return [ map {
        my $pair = $_;
        map { {
          experimental_subject => $pair->experimental_subject,
          control_subject => $pair->control_subject,
          #TODO - this should be in config or on the pairing object
          subject => $pair->experimental_subject->source,
          %$_
        } } @$model_hashes
    } @subject_pairings ];
}

sub _get_items_to_process {
    my $self = shift;

    if ($self->instrument_data) {
        return Genome::Config::AnalysisProject::InstrumentDataBridge->get(
            instrument_data_id => [map { $_->id } $self->instrument_data],
            -hint => ['analysis_project', 'instrument_data', 'instrument_data.sample']
        );
    } else {
        return Genome::Config::AnalysisProject::InstrumentDataBridge->get(
            status => ['new', 'failed'],
            -hint => ['analysis_project', 'instrument_data', 'instrument_data.sample'],
            -order => ['fail_count'],
            -limit => $self->limit,
        );
    }
}

sub _assign_model_to_analysis_project {
    my $self = shift;
    my $analysis_project = shift;
    my $model = shift;
    die('Must specify an anlysis project and a model!') unless $analysis_project && $model;

    return $analysis_project->model_group->assign_models($model);
}

sub _update_models_for_associated_projects {
    my $self = shift;
    my $instrument_data = shift;

    my @projects = Genome::Project->get('parts.entity_id' => $instrument_data->id);

    if(@projects) {
        my $update_cmd = Genome::Project::Command::Update::Models->create(
            projects => \@projects
        );

        die $self->error_message('Failed to update models for project associated with %s', $instrument_data->__display_name__)
            unless $update_cmd->execute();
    }

    return 1;
}

sub _lock {
    unless ($ENV{UR_DBI_NO_COMMIT}) {
        my $lock_var = $ENV{GENOME_LOCK_DIR} . '/genome_config_command_configure-queued-instrument-data/lock';
        my $lock = Genome::Sys->lock_resource(resource_lock => $lock_var, max_try => 1);

        die('Unable to acquire the lock! Is ConfigureQueuedInstrumentData already running or did it exit uncleanly?')
            unless $lock;

        UR::Context->current->add_observer(
            aspect => 'commit',
            callback => sub {
                Genome::Sys->unlock_resource(resource_lock => $lock);
            }
        );
    }
}

#It's lame that these methods need to exist - is there a way to clean the data before it comes over?
sub _normalize_domain {
    my $domain = lc(shift);
    if ($domain eq 'unknown') {
        return 'eukaryota';
    }
    return $domain;
}

sub _normalize_taxon {
    my $taxon = lc(shift);
    if ($taxon =~ /mus musculus/i || $taxon =~ /mouse/i) {
        return 'mus_musculus';
    } elsif ($taxon =~ /homo sapien/i || $taxon =~ /human/i) {
        return 'homo_sapien';
    } elsif ($taxon =~ /maize/i) {
        return 'maize';
    }
}

sub _normalize_extraction_type {
    my $type = lc(shift);
    if ($type =~ /rna/i || $type =~ /cdna/i) {
        return 'rna';
    } elsif ($type =~ /[^c]dna/i) {
        return 'genomic_dna';
    }
    return $type
}

1;
