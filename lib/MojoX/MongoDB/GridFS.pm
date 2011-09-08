package MojoX::MongoDB::GridFS;
use Mojo::Base -base;

use MojoX::MongoDB::GridFS::File;
use DateTime;
use Digest::MD5;
use Carp;

$MojoX::MongoDB::GridFS::chunk_size = 1048576;

has _database => sub { undef };
has prefix    => sub { undef };

has files => sub {
    my $self = shift;
    my $coll = $self->_database->get_collection( $self->prefix . '.files' );
    return $coll;
};

has chunks => sub {
    my $self = shift;
    my $coll = $self->_database->get_collection( $self->prefix . '.chunks' );
    return $coll;
};

sub _ensure_indexes {
    my $self = shift;

    # ensure the necessary index is present (this may be first usage)
    $self->files->ensure_index( Tie::IxHash->new( filename => 1 ),
        { "safe" => 1 } );
    $self->chunks->ensure_index( Tie::IxHash->new( files_id => 1, n => 1 ),
        { "safe" => 1 } );
}

sub get {
    my ( $self, $id ) = @_;

    return $self->find_one( { _id => $id } );
}

sub put {
    my ( $self, $fh, $metadata ) = @_;
    return $self->insert( $fh, $metadata, { safe => 1 } );
}

sub delete {
    my ( $self, $id ) = @_;
    $self->remove( { _id => $id }, { safe => 1 } );
}

sub find_one {
    my ( $self, $criteria, $fields ) = @_;

    my $file = $self->files->find_one( $criteria, $fields );
    return undef unless $file;
    return MojoX::MongoDB::GridFS::File->new(
        { _grid => $self, info => $file } );
}

sub remove {
    my ( $self, $criteria, $options ) = @_;

    my $just_one = 0;
    my $safe     = 0;

    if ( defined $options ) {
        if ( ref $options eq 'HASH' ) {
            $just_one = $options->{just_one} && 1;
            $safe     = $options->{safe}     && 1;
        }
        elsif ($options) {
            $just_one = $options && 1;
        }
    }

    $self->_ensure_indexes;

    if ($just_one) {
        my $meta = $self->files->find_one($criteria);
        $self->chunks->remove( { "files_id" => $meta->{'_id'} },
            { safe => $safe } );
        $self->files->remove( { "_id" => $meta->{'_id'} }, { safe => $safe } );
    }
    else {
        my $cursor = $self->files->query($criteria);
        while ( my $meta = $cursor->next ) {
            $self->chunks->remove( { "files_id" => $meta->{'_id'} },
                { safe => $safe } );
        }
        $self->files->remove( $criteria, { safe => $safe } );
    }
}

sub insert {
    my ( $self, $fh, $metadata, $options ) = @_;
    $options ||= {};

    confess "not a file handle" unless $fh;
    $metadata = {} unless $metadata && ref $metadata eq 'HASH';

    $self->_ensure_indexes;

    my $start_pos = $fh->getpos();

    my $id;
    if ( exists $metadata->{"_id"} ) {
        $id = $metadata->{"_id"};
    }
    else {
        $id = MojoX::MongoDB::OID->new;
    }

    my $n      = 0;
    my $length = 0;
    while (
        (
            my $len = $fh->read( my $data, $MojoX::MongoDB::GridFS::chunk_size )
        ) != 0
      )
    {
        $self->chunks->insert(
            {
                "files_id" => $id,
                "n"        => $n,
                "data"     => bless( \$data )
            },
            $options
        );
        $n++;
        $length += $len;
    }
    $fh->setpos($start_pos);

    # get an md5 hash for the file
    my $result = $self->_database->run_command(
        { "filemd5", $id, "root" => $self->prefix } );

    # compare the md5 hashes
    if ( $options->{safe} ) {
        my $md5 = Digest::MD5->new;
        $md5->addfile($fh);
        my $digest = $md5->hexdigest;
        if ( $digest ne $result->{md5} ) {

            # cleanup and die
            $self->chunks->remove( { files_id => $id } );
            die "md5 hashes don't match: database got $result->{md5}, fs got $digest";
        }
    }

    my %copy = %{$metadata};
    $copy{"_id"}        = $id;
    $copy{"md5"}        = $result->{"md5"};
    $copy{"chunkSize"}  = $MojoX::MongoDB::GridFS::chunk_size;
    $copy{"uploadDate"} = DateTime->now;
    $copy{"length"}     = $length;
    return $self->files->insert( \%copy, $options );
}

sub drop {
    my ($self) = @_;

    $self->files->drop;
    $self->chunks->drop;
}

sub all {
    my ($self) = @_;
    my @ret;

    my $cursor = $self->files->query;
    while ( my $meta = $cursor->next ) {
        push @ret,
          MojoX::MongoDB::GridFS::File->new(
            _grid => $self,
            info  => $meta
          );
    }
    return @ret;
}

1;

__END__

=head1 NAME

MojoX::MongoDB::GridFS - A file storage utility

=head1 SYNOPSIS

    use MojoX::MongoDB::GridFS;

    my $grid = $database->get_gridfs;
    my $fh = IO::File->new("myfile", "r");
    $grid->insert($fh, {"filename" => "mydbfile"});

=head1 DESCRIPTION

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>
