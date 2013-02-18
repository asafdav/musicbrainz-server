package MusicBrainz::Server::Controller::Role::Annotation;
use Moose::Role -traits => 'MooseX::MethodAttributes::Role::Meta::Role';

use MusicBrainz::Server::Constants qw( :annotation );
use MusicBrainz::Server::Data::Utils qw( model_to_type );
use MusicBrainz::Server::Translation qw( l ln );
use MusicBrainz::Server::Validation qw( is_positive_integer );

use MusicBrainz::Server::NES::Controller::Utils qw( run_update_form );

requires 'load', 'show';

my %model_to_edit_type = (
    Artist => $EDIT_ARTIST_ADD_ANNOTATION,
    Label => $EDIT_LABEL_ADD_ANNOTATION,
    Recording => $EDIT_RECORDING_ADD_ANNOTATION,
    Release => $EDIT_RELEASE_ADD_ANNOTATION,
    ReleaseGroup => $EDIT_RELEASEGROUP_ADD_ANNOTATION,
    Work => $EDIT_WORK_ADD_ANNOTATION,
);

after 'load' => sub
{
    my ($self, $c) = @_;
    my $entity = $c->stash->{entity};
    my $model = $self->{model};

    $c->model('MB')->with_nes_transaction(sub {
        $c->model($model)->load_annotation($entity);
    });
};

sub latest_annotation : Chained('load') PathPart('annotation')
{
    my ($self, $c) = @_;
    my $entity = $c->stash->{entity};
    my $model = $self->{model};

    my $annotation = $c->model($self->{model})->annotation->get_latest($entity->id);

    $c->model('Editor')->load($annotation);

    my $annotation_model = $c->model($model)->annotation;
    my $annotations = $self->_load_paged(
        $c, sub {
            $annotation_model->get_history($entity->id, @_);
        }
    );

    $c->stash(
        annotation => $annotation,
        number_of_revisions => scalar @$annotations,
        template   => $self->action_namespace . '/annotation_revision.tt'
    );
}

sub annotation_revision : Chained('load') PathPart('annotation') Args(1)
{
    my ($self, $c, $id) = @_;
    my $entity = $c->stash->{entity};
    my $model = $self->{model};

    my $annotation = $c->model($self->{model})->annotation->get_by_id($id)
        or $c->detach('/error_404');

    $c->model('Editor')->load($annotation);

    my $annotation_model = $c->model($model)->annotation;
    my $annotations = $self->_load_paged(
        $c, sub {
            $annotation_model->get_history($entity->id, @_);
        }
    );

    $c->stash(
        annotation => $annotation,
        number_of_revisions => scalar @$annotations,
    );
}

after 'show' => sub
{
    my ($self, $c) = @_;
    my $entity = $c->stash->{entity};
    my $model = $self->{model};

    my $annotation = $c->stash->{entity}->{latest_annotation};
    $c->model('Editor')->load($annotation);
};

after 'load' => sub {
    my ($self, $c) = @_;

    # my (undef, $no) = $c->model($self->{model})->annotation
    #     ->get_history($c->stash->{entity}->id, 50, 0);

    # $c->stash(
    #     number_of_revisions => $no,
    # );
};

sub edit_annotation : Chained('load') PathPart RequireAuth Edit
{
    my ($self, $c) = @_;

    my $model = $self->{model};
    my $entity = $c->stash->{entity};
    $c->model($model)->load_annotation($entity);

    my $form = $c->form(
        form        => 'Annotation',
        init_object => {
            text        => $entity->latest_annotation->text,
            revision_id => $entity->revision_id
        },
    );

    if ($c->form_posted && $form->submitted_and_valid($c->req->params)) {
        if ($form->field('preview')->input) {
            $c->stash(
                show_preview => 1,
                preview      => $form->field('text')->value
            );
        }
        else
        {
            run_update_form(
                $self, $c, $form,
                build_tree => sub {
                    my $values = shift;

                    return $self->{tree_entity}->new(
                        annotation => $values->{text}
                    );
                }
            );

            $c->response->redirect($c->uri_for_action($self->action_for('show'), [ $entity->gid ]));
            $c->detach;
        }
    }
}

sub annotation_history : Chained('load') PathPart('annotations') RequireAuth
{
    my ($self, $c) = @_;

    my $model            = $self->{model};
    my $entity           = $c->stash->{entity};
    my $annotation_model = $c->model($model)->annotation;

    my $annotations = $self->_load_paged(
        $c, sub {
            $annotation_model->get_history($entity->id, @_);
        }
    );

    $c->model('Editor')->load(@$annotations);
    $c->stash( annotations => $annotations );
}

sub annotation_diff : Chained('load') PathPart('annotations-differences') RequireAuth
{
    my ($self, $c) = @_;

    my $model            = $self->{model};
    my $entity           = $c->stash->{entity};
    my $annotation_model = $c->model($model)->annotation;

    my $old = $c->req->query_params->{old};
    my $new = $c->req->query_params->{new};

    unless (is_positive_integer($old) &&
            is_positive_integer($new) &&
            $old != $new) {
        $c->stash(
            message => l('The old and new annotation ids must be unique, positive integers.')
        );
        $c->detach('/error_400')
    }

    my $old_annotation = $annotation_model->get_by_id($old);
    my $new_annotation = $annotation_model->get_by_id($new);

    $c->model('Editor')->load($new_annotation);
    $c->model('Editor')->load($old_annotation);

    $c->stash(
        old => $old_annotation,
        new => $new_annotation
    );
}

no Moose::Role;
1;

