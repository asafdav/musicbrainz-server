package MusicBrainz::Server::NES::Controller::Utils;
use strict;
use warnings;

use Scalar::Util qw( blessed );
use Sub::Exporter -setup => {
    exports => [qw( create_edit create_update )]
};

sub create_edit {
    my ($controller, $c, %opts) = @_;

    my $form = do {
        my $f = $opts{form};
        if (blessed($f)) {
            $f;
        }
        else {
            my %args = (
                ctx => $c,
            );

            $args{init_object} = $opts{subject}
                if defined $opts{subject};

            $c->form(form => $f, %args);
        }
    };

    if ($c->form_posted && $form->submitted_and_valid($c->req->body_params)) {
        my $values = $form->values;
        my $edit = $c->model('NES::Edit')->open;

        my $work = $opts{on_post}->($values, $edit);

        if ($values->{edit_note}) {
            $c->model('EditNote')->add_note(
                $edit->id,
                {
                    editor_id => $c->user->id,
                    text => $values->{edit_note}
                }
            );
        }

        # NES:
        # my $privs = $c->user->privileges;
        # if ($c->user->is_auto_editor &&
        #     $form->field('as_auto_editor') &&
        #     !$form->field('as_auto_editor')->value) {
        # }

        $c->response->redirect(
            $c->uri_for_action($controller->action_for('show'), [ $work->gid ]));
    }
    elsif (!$c->form_posted && %{ $c->req->query_params }) {
        $form->process( params => $c->req->query_params );
        $form->clear_errors;
    }
}

sub create_update {
    my ($controller, $c, %opts) = @_;
    create_edit(
        $controller, $c,
        %opts,
        on_post => sub {
            my ($values, $edit) = @_;
            my $revision = $c->model( $controller->{model} )->get_revision(
                $values->{revision_id});

            $c->model( $controller->{model} )->update(
                $edit, $c->user, $revision,
                $opts{build_tree}->($values, $revision)
            );

            return $revision;
        }
    );
}

1;
