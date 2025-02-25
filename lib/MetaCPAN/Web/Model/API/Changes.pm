package MetaCPAN::Web::Model::API::Changes;
use Moose;
extends 'MetaCPAN::Web::Model::API';

use MetaCPAN::Web::Model::API::Changes::Parser ();
use Ref::Util                                  qw( is_arrayref );
use Future                                     ();

sub get {
    my ( $self, @path ) = @_;
    $self->request( '/changes/' . join( '/', @path ) );
}

sub release_changes {
    my ( $self, $path, %opts ) = @_;
    $path = join '/', @$path
        if is_arrayref($path);
    $self->get($path)->then( sub {
        my $file = shift;

        my $content = $file->{content}
            or return Future->done( { code => 404 } );

        my $version
            = _parse_version( $opts{version} || $file->{version} );

        my @releases = _releases($content);

        my @changelogs;
        while ( my $r = shift @releases ) {
            if ( _versions_eq( $r->{version_parsed}, $version ) ) {
                $r->{current} = 1;
                push @changelogs, $r;
                if ( $opts{include_dev} ) {
                    for my $dev_r (@releases) {
                        last
                            if !$dev_r->{dev};
                        push @changelogs, $dev_r;
                    }
                }
            }
        }
        return Future->done( {
            changes => \@changelogs,
        } );
    } );
}

sub by_releases {
    my ( $self, $releases ) = @_;

    my %release_lookup = map { ( $_->[0] . '/' . $_->[1] ) => $_ } @$releases;
    my $path           = 'by_releases?'
        . join( '&', map { 'release=' . $_ } keys %release_lookup );
    $self->get($path)->transform(
        done => sub {
            my $response = shift;
            my @changes  = @{ $response->{changes} };

            my @changelogs;
            for my $change (@changes) {
                next unless $change->{release} =~ m/-([0-9_\.]+(-TRIAL)?)\z/;
                my $version  = _parse_version($1);
                my @releases = _releases( $change->{changes_text} );

                while ( my $r = shift @releases ) {
                    if ( _versions_eq( $r->{version_parsed}, $version ) ) {
                        $r->{current} = 1;

                        # Used in Controller/Feed.pm Line 37
                        $r->{author} = $change->{author};
                        $r->{name}   = $change->{release};

                        push @changelogs, $r;
                        last;
                    }
                }
            }
            return \@changelogs;
        }
    );
}

sub _releases {
    my ($content) = @_;
    my $changelog
        = MetaCPAN::Web::Model::API::Changes::Parser->parse($content);

    my @releases = sort {
        my $a_v = $a->{version_parsed};
        my $b_v = $b->{version_parsed};
        if ( !ref $a_v || !ref $b_v ) {
            $a_v = "$a_v";
            $b_v = "$b_v";
        }
        $a_v cmp $b_v;
        }
        map {
        my $v     = _parse_version( $_->{version} );
        my $trial = $_->{version} =~ /-TRIAL$/
            || $_->{note} && $_->{note} =~ /\bTRIAL\b/;
        my $dev = $trial || $_->{version} =~ /_/;
        +{
            %$_,
            version_parsed => $v,
            trial          => $trial,
            dev            => $dev,
        };
        } @{ $changelog->{releases} || [] };
    return @releases;
}

sub _versions_eq {
    my ( $v1, $v2 ) = @_;

    # we're comparing version objects
    if ( ref $v1 && ref $v2 ) {
        return $v1 eq $v2;
    }

    # if one version failed to parse, force string comparison so version's
    # overloads don't try to inflate the other version
    else {
        return "$v1" eq "$v2";
    }
}

sub _parse_version {
    my ($v) = @_;
    $v =~ s/-TRIAL$//;
    $v =~ s/_//g;
    $v =~ s/\A0+(\d)/$1/;
    use warnings FATAL => 'all';
    eval { $v = version->parse($v) };
    return $v;
}

__PACKAGE__->meta->make_immutable;

1;
