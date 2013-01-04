package Genome::Model::Command::Define;

use strict;
use warnings;

use Genome;
use Genome::Model::Command::Define::Helper;

class Genome::Model::Command::Define {
    is => 'Command::SubCommandFactory',
};

# Compiling this class autogenerates one sub-command per model type.
# These are the commands which actually execute, and either inherit from this
# class or from those returned by _sub_commands_inherit_from.
sub _sub_commands_from { 'Genome::Model' }

# Sub commands generated by this class will inherit from the class(es) specified here.
# This is overridden in Genome::Model define_by().
#sub _sub_commands_inherit_from {'Genome::Model::Command::Define::Helper'}

sub _build_sub_command {
    my ($self, $class_name) = @_;

    my $model_subclass_name = $class_name;
    $model_subclass_name =~ s/::Command::Define::/::/;

    # Instead of having everything which does not use ::Helper be fully hand-implemented,
    # let it figure out the base class to use dynamically.
    my $base_class = $model_subclass_name->define_by;
    $base_class->class;
    my @inheritance = ($base_class);

    my $model_subclass_meta = UR::Object::Type->get($model_subclass_name);
    if ($model_subclass_meta and $model_subclass_name->isa('Genome::Model')) {
        my $build_subclass_meta = UR::Object::Type->define(
            class_name => $class_name,
            is => \@inheritance,
        );
        return $class_name;
    }

    return;
}

1;
