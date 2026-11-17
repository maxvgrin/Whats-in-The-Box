function [enabled, workers] = mva_parallel_setup(cfg)
enabled=false; workers=4;
if ~isfield(cfg,'enableParallel') || ~cfg.enableParallel, return; end
if isfield(cfg,'workers'), workers=cfg.workers; end
if ~isnumeric(workers) || ~isscalar(workers) || ~isfinite(workers) || workers<1 || fix(workers)~=workers
    error('mva:workers','Workers must be a positive integer.');
end
try
    if ~license('test','Distrib_Computing_Toolbox') || exist('parpool','file')~=2
        warning('mva:noParallel','Parallel Computing Toolbox unavailable; using sequential processing.'); return;
    end
    pool=gcp('nocreate');
    if ~isempty(pool) && isa(pool,'parallel.ThreadPool')
        warning('mva:threadPool','Osprey needs process isolation; using sequential processing with the existing thread pool.'); return;
    end
    if isempty(pool), pool=parpool('local',workers); end
    workers=min(workers,pool.NumWorkers);
    enabled=true;
    fprintf('[mva] Parallel Osprey localisation: up to %d process workers.\n',workers);
catch ME
    warning('mva:parallelFallback','Cannot start process pool (%s); using sequential processing.',ME.message);
end
end
