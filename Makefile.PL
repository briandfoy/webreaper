# $Id$
use ExtUtils::MakeMaker;

sub ExtUtils::MM_Any::test_via_harness
	{
    my($self, $perl, $tests) = @_;

    return qq|\t$perl "-MTest::Manifest" | .
           qq|"-e" "run_t_manifest(\$(TEST_VERBOSE), '\$(INST_LIB)', | .
           qq|'\$(INST_ARCHLIB)')"\n|;
	}

WriteMakefile(
    'NAME'		    => 'webreaper',
	'VERSION'       => '0.10',
	
	'EXE_FILES' =>  [ 'webreaper' ],
	    	
	'PREREQ_PM' => {
		'File::Find::Rule'  => '0',
		'Test::Manifest'    => '0.9',
		'Test::More'        => '0',
		'Test::Pod'         => '0.90',
		},

	);
