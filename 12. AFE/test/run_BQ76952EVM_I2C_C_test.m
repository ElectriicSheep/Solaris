function run_BQ76952EVM_I2C_C_test
%RUN_BQ76952EVM_I2C_C_TEST Run the independent transaction-level C test in MATLAB.
afe=fileparts(fileparts(mfilename('fullpath')));
testDir=fullfile(afe,'test'); repo=fileparts(afe);
mex('-R2018a','-outdir',testDir,['-I' afe], ...
    ['-I' fullfile(repo,'13. Pi','libresolar')], ...
    fullfile(testDir,'test_i2c_transaction_mex.c'), ...
    fullfile(afe,'bq76952_emul.c'));
addpath(testDir);
test_i2c_transaction_mex;
end
