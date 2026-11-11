function [t, d] = getLoggedSignal(out, name, layer)
%GETLOGGEDSIGNAL Time and data of a logged signal, found by name and layer.
%   [t, d] = getLoggedSignal(out, "vGroup", "SENS") returns the signal named
%   vGroup that was logged inside the SENS subsystem.
%   t is N x 1; d is N x channels, whatever shape Simulink logged it in.
%   Repeated time points (solver restarts) are removed, keeping the last.

    ds = out.logsout;
    ts = [];
    for k = 1:ds.numElements
        el = ds.getElement(k);
        if string(el.Name) ~= name, continue, end
        if contains(string(el.BlockPath.getBlock(1)), "/" + layer)
            ts = el.Values;
            break
        end
    end
    assert(~isempty(ts), "Signal '%s' inside %s is not logged. " + ...
        "Right-click that line > Log Selected Signals.", name, layer);

    t = ts.Time(:);
    d = squeeze(ts.Data);
    if size(d, 1) ~= numel(t), d = d.'; end
    [t, iu] = unique(t, "last");
    d = d(iu, :);
end
