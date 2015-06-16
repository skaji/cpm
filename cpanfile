requires 'perl', '5.008005';

requires 'Menlo::CLI::Compat', git => 'git://github.com/miyagawa/cpanminus.git', ref => 'menlo';

on test => sub {
    requires 'Test::More', '0.96';
};
