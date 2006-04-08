#!/usr/bin/perl

use Test::More tests=>8;

BEGIN {
    use_ok( 'Chroniton' );
}

BEGIN {
    use_ok( 'Chroniton::Config' );
}

BEGIN {
    use_ok( 'Chroniton::Messages' );
}

BEGIN {
    use_ok( 'Chroniton::Message' );
}

BEGIN {
    use_ok( 'Chroniton::Event' );
}

BEGIN {
    use_ok( 'Chroniton::Backup' );
}

BEGIN {
    use_ok( 'Chroniton::State' );
}

BEGIN {
    use_ok( 'Chroniton::Event::FileInSet' );
}
