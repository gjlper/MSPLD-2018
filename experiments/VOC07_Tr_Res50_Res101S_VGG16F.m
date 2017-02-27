figure('visible', 'off');
clear; close all; clc;
clear mex;
clear is_valid_handle; % to clear init_key
%run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'startup'));
%% -------------------- CONFIG --------------------
opts.caffe_version          = 'caffe';
opts.gpu_id                 = auto_select_gpu;
active_caffe_mex(opts.gpu_id, opts.caffe_version);

% global parameters
extra_para                  = load(fullfile(pwd, 'models', 'pre_trained_models', 'box_param.mat'));
classes                     = extra_para.VOCopts.classes;
rng_seed                    = 5;
per_class_sample            = 3;
print_result                = true;
use_flipped                 = true;
gamma                       = 0.2;
base_select                 = [2, 3.5];
% model
models                      = cell(3,1);
box_param                   = cell(3,1);
models{1}.solver_def_file   = fullfile(pwd, 'models', 'rfcn_prototxts', 'ResNet-50L_OHEM_res3a', 'solver_lr1_3.prototxt');
models{1}.test_net_def_file = fullfile(pwd, 'models', 'rfcn_prototxts', 'ResNet-50L_OHEM_res3a', 'test.prototxt');
models{1}.net_file          = fullfile(pwd, 'models', 'pre_trained_models', 'ResNet-50L', 'ResNet-50-model.caffemodel');
models{1}.cur_net_file      = 'unset';
models{1}.name              = 'ResNet50-OHEM';
models{1}.mean_image        = fullfile(pwd, 'models', 'pre_trained_models', 'ResNet-50L', 'mean_image.mat');
models{1}.conf              = rfcn_config_ohem('image_means', models{1}.mean_image, ...
                                               'classes', classes, ...
                                               'max_epoch', 8, 'step_epoch', 7, ...
                                               'regression', true);
box_param{1}                = load(fullfile(pwd, 'models', 'pre_trained_models', 'box_param.mat'));

models{2}.solver_def_file   = fullfile(pwd, 'models', 'rfcn_prototxts', 'ResNet-101L_res3a', 'solver_lr1_3.prototxt');
models{2}.test_net_def_file = fullfile(pwd, 'models', 'rfcn_prototxts', 'ResNet-101L_res3a', 'test.prototxt');
models{2}.net_file          = fullfile(pwd, 'models', 'pre_trained_models', 'ResNet-101L', 'ResNet-101-model.caffemodel');
models{2}.cur_net_file      = 'unset';
models{2}.name              = 'ResNet101-SIMPLE';
models{2}.mean_image        = fullfile(pwd, 'models', 'pre_trained_models', 'ResNet-101L', 'mean_image.mat');
models{2}.conf              = rfcn_config_simple('image_means', models{2}.mean_image, ...
                                               'classes', classes, ...
                                               'max_epoch', 8, 'step_epoch', 7, 'regression', true);
box_param{2}                = load(fullfile(pwd, 'models', 'pre_trained_models', 'box_param.mat'));

models{3}.solver_def_file   = fullfile(pwd, 'models', 'fast_rcnn_prototxts', 'vgg_16layers_conv3_1', 'solver_lr1_3.prototxt');
models{3}.test_net_def_file = fullfile(pwd, 'models', 'fast_rcnn_prototxts', 'vgg_16layers_conv3_1', 'test.prototxt');
models{3}.net_file          = fullfile(pwd, 'models', 'pre_trained_models', 'VGG16', 'vgg16.caffemodel');
models{3}.cur_net_file      = 'unset';
models{3}.name              = 'VGG16-Fast';
models{3}.mean_image        = fullfile(pwd, 'models', 'pre_trained_models', 'VGG16', 'mean_image.mat');
models{3}.conf              = fast_rcnn_config('image_means', models{3}.mean_image, ...
                                                 'classes', extra_para.VOCopts.classes, ...
                                                 'max_epoch', 9, 'step_epoch', 8, 'regression', true);
box_param{3}                = load(fullfile(pwd, 'models', 'pre_trained_models', 'fast_box_param.mat'));

% cache name
opts.cache_name             = ['EWSD_Tr_', models{1}.name, '_', models{2}.name, '_', models{3}.name];
opts.cache_name             = [opts.cache_name, '_per-', num2str(mean(per_class_sample)), '_seed-', num2str(rng_seed)];
% train/test data
fprintf('Loading dataset...');
dataset                     = [];
dataset                     = Dataset.voc2007_trainval_ss(dataset, 'train', use_flipped);
dataset                     = Dataset.voc2007_test_ss(dataset, 'test', false);
fprintf('Done.\n');

fprintf('-------------------- TRAINING --------------------\n');
train_time                  = tic;
opts.rfcn_model             = weakly_co_train_v2(dataset.imdb_train, dataset.roidb_train, models, ...
                                'cache_name',       opts.cache_name, ...
                                'per_class_sample', per_class_sample, ...
                                'base_select',      base_select, ...
                                'rng_seed',         rng_seed, ...
                                'use_flipped',      use_flipped, ...
                                'gamma',            gamma, ...
                                'debug',            print_result, ...
                                'box_param',        box_param);
assert(isfield(opts, 'rfcn_model') ~= 0, 'not found trained model');
train_time                  = toc(train_time);

fprintf('-------------------- TESTING --------------------\n');
assert(numel(opts.rfcn_model) == numel(models));
mAPs                        = cell(numel(models), 1);
test_time                   = tic;
net_defs                    = [];
net_models                  = [];
net_confs                   = [];
for idx = 1:numel(models)
    mAPs{idx}               = weakly_co_test_mAP({models{idx}.conf}, dataset.imdb_test, dataset.roidb_test, ...
                                'net_defs',         {models{idx}.test_net_def_file}, ...
                                'net_models',       opts.rfcn_model(idx), ...
                                'cache_name',       opts.cache_name,...
                                'log_prefix',       [models{idx}.name, '_final_'],...
                                'ignore_cache',     true);
    net_defs{idx}           = models{idx}.test_net_def_file;
    net_models{idx}         = opts.rfcn_model{idx};
    net_confs{idx}          = models{idx}.conf;
end
mAPs{numel(models)+1}       = weakly_test_mAP_v2(net_confs, dataset.imdb_test, dataset.roidb_test, ...
                                'net_defs',         net_defs, ...
                                'net_models',       net_models, ...
                                'cache_name',       opts.cache_name,...
                                'log_prefix',       ['Co_final_'],...
                                'ignore_cache',     true);
test_time                   = toc(test_time);
loc_dataset                 = Dataset.voc2007_trainval_ss([], 'train', false);
Corloc                      = weakly_test_Cor_v2(net_confs, loc_dataset.imdb_train{1}, loc_dataset.roidb_train{1}, ...
                                'net_defs',         net_defs, ...
                                'net_models',       net_models, ...
                                'cache_name',       opts.cache_name,...
                                'ignore_cache',     true);
for idx = 1:numel(models)
    fprintf('%s mAP : %.3f\n', models{idx}.name, mAPs{idx});
end
fprintf('Training Cost : %.1f s, Test Cost : %.1f s, mAP : %.2f, Corloc : %.2f\n', train_time, test_time, mAPs{numel(models)+1}, Corloc);

fprintf('----------------------------------All Test-----------------------------\n');
imdbs_name          = cell2mat(cellfun(@(x) x.name, dataset.imdb_train,'UniformOutput', false));
all_test_time       = tic;
rfcn_model          = cell(numel(models), numel(base_select)+1);
for iter = 0:numel(base_select)
  for idx = 1:numel(models)
    rfcn_model{idx, iter+1} = fullfile(pwd, 'output', 'weakly_cachedir' , opts.cache_name, imdbs_name, [models{idx}.name, '_Loop_', num2str(iter), '_final.caffemodel']);
	assert(exist(rfcn_model{idx, iter+1}, 'file') ~= 0, 'not found trained model');
  end
end
S_mAPs              = zeros(numel(models)+1, size(rfcn_model,2));
for index = 1:size(rfcn_model, 2)
  merge_model_def = cell(numel(models), 1);
  weigh_model_def = cell(numel(models), 1);
  for idx = 1:numel(models)
    S_mAPs(idx, index) = weakly_test_mAP_v2(net_confs(idx), dataset.imdb_test, dataset.roidb_test, ...
                             'net_defs',         {models{idx}.test_net_def_file}, ...
                             'net_models',       rfcn_model(idx,index), ...
                             'test_iteration',   1, ...
                             'cache_name',       opts.cache_name, ...
                             'log_prefix',       [models{idx}.name, '_', num2str(index-1), '_'], ...
                             'ignore_cache',     true);
    merge_model_def{idx} = models{idx}.test_net_def_file;
    weigh_model_def{idx} = rfcn_model{idx,index};
  end
  S_mAPs(end, index)   = weakly_test_mAP_v2(net_confs, dataset.imdb_test, dataset.roidb_test, ...
                             'net_defs',         merge_model_def, ...
                             'net_models',       weigh_model_def, ...
                             'test_iteration',   1, ...
                             'cache_name',       opts.cache_name, ...
                             'log_prefix',       [cell2mat(cellfun(@(x) x.name, models', 'UniformOutput', false)), '_', num2str(index-1), '_'], ...
                             'ignore_cache',     true);
end
all_test_time = toc(all_test_time);
fprintf('Training Cost : %.1f s, Test Cost : %.1f s, All Test Cost : %.1f s\n', train_time, test_time, all_test_time);
