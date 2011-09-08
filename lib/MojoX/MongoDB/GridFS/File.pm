package MojoX::MongoDB::GridFS::File;
use Mojo::Base -base;

use MojoX::MongoDB::GridFS;
use IO::File;

has _grid => sub { undef };
has info  => sub { undef };

sub print {
    my ( $self, $fh, $length, $offset ) = @_;
    $offset ||= 0;
    $length ||= 0;
    my ( $written, $pos ) = ( 0, 0 );
    my $start_pos = $fh->getpos();

    $self->_grid->chunks->ensure_index(
        Tie::IxHash->new( files_id => 1, n => 1 ) );

    my $cursor =
      $self->_grid->chunks->query( { "files_id" => $self->info->{"_id"} } )
      ->sort( { "n" => 1 } );

    while (( my $chunk = $cursor->next )
        && ( !$length || $written < $length ) )
    {
        my $len = length $chunk->{'data'};

        # if we are cleanly beyond the offset
        if ( !$offset || $pos >= $offset ) {
            if ( !$length || $written + $len < $length ) {
                $fh->print( $chunk->{"data"} );
                $written += $len;
                $pos     += $len;
            }
            else {
                $fh->print( substr( $chunk->{'data'}, 0, $length - $written ) );
                $written += $length - $written;
                $pos     += $length - $written;
            }
            next;
        }

        # if the offset goes to the middle of this chunk
        elsif ( $pos + $len > $offset ) {

            # if the length of this chunk is smaller than the desired length
            if ( !$length || $len <= $length - $written ) {
                $fh->print(
                    substr(
                        $chunk->{'data'},
                        $offset - $pos,
                        $len - ( $offset - $pos )
                    )
                );
                $written += $len - ( $offset - $pos );
                $pos     += $len - ( $offset - $pos );
            }
            else {
                $fh->print(
                    substr( $chunk->{'data'}, $offset - $pos, $length ) );
                $written += $length;
                $pos     += $length;
            }
            next;
        }

        # if the offset is larger than this chunk
        $pos += $len;
    }
    $fh->setpos($start_pos);
    return $written;
}

sub slurp {
    my ( $self, $length, $offset ) = @_;
    my $bytes   = '';
    my $fh      = new IO::File \$bytes, '+>';
    my $written = $self->print( $fh, $length, $offset );

    # some machines don't set $bytes
    if ( $written and !length($bytes) ) {
        my $retval;
        read $fh, $retval, $written;
        return $retval;
    }

    return $bytes;
}

1;

__END__

=head1 NAME

MojoX::MongoDB::GridFS::File - A Mongo GridFS file

=head1 SYNOPSIS

    use MojoX::MongoDB::GridFS::File;

    my $outfile = IO::File->new("outfile", "w");
    my $file = $grid->find_one;
    $file->print($outfile);

=head1 DESCRIPTION

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>
