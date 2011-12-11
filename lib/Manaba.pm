package Manaba;
use Dancer ':syntax';

our $VERSION = '0.1';

get '/' => sub {
    template 'index' => {
        items => [
        ],
    };
};

get '/update/:id?' => sub {
    my $id = param('id');

    if ($id) {
        update($id);
    }
    else {
        update_all();
    }

    redirect '/';
};

sub update {
    my $id = shift;
}

sub update_all {
}

true;
