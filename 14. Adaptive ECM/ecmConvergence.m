classdef ecmConvergence < handle
%ECMCONVERGENCE Convergence clocks for the adaptive ECM, per group and parameter.
%
% Rule (fixed before any results): a parameter of a group has converged when its
% relative error stays within +/- band (default 1 %) for hold seconds (default 600 s)
% of simulated time. The convergence time and energy are those at the START of that
% window. If the error later leaves the band, the time it left is recorded too.
%
% Errors (estimate vs truth at the true operating point):
%   R0, R1, tau1  the table values the EKF uses (at the estimated SOC and the measured
%                 temperature) vs the true values at the true SOC and temperature
%   Q             the capacity estimate vs the true capacity
% Energy: Wh through each group since the start of the run (charge and discharge).

    properties
        band = 0.01
        hold = 600
        names = ["R0" "R1" "tau1" "Q"]
        since            % 13 x 4, start of the current in-band window (NaN if out)
        whSince          % 13 x 4, Wh at that start
        convT            % 13 x 4, convergence time (s), NaN until converged
        convWh           % 13 x 4, Wh at convergence
        leftT            % 13 x 4, first time the error left the band after convergence
        tNow = 0
        whNow = zeros(1, 13)
    end

    methods
        function obj = ecmConvergence(band, hold)
            if nargin >= 1, obj.band = band; end
            if nargin >= 2, obj.hold = hold; end
            obj.since = nan(13, 4); obj.whSince = nan(13, 4);
            obj.convT = nan(13, 4); obj.convWh = nan(13, 4); obj.leftT = nan(13, 4);
        end

        function add(obj, t, E, Wh)
            % t: N x 1 times (s); E: N x 13 x 4 relative errors; Wh: N x 13
            for p = 1:4
                for g = 1:13
                    e = abs(E(:, g, p)) <= obj.band;
                    for j = 1:numel(t)
                        if e(j)
                            if isnan(obj.since(g, p))
                                obj.since(g, p) = t(j); obj.whSince(g, p) = Wh(j, g);
                            end
                            if isnan(obj.convT(g, p)) && t(j) - obj.since(g, p) >= obj.hold
                                obj.convT(g, p) = obj.since(g, p); obj.convWh(g, p) = obj.whSince(g, p);
                            end
                        else
                            obj.since(g, p) = NaN;
                            if ~isnan(obj.convT(g, p)) && isnan(obj.leftT(g, p))
                                obj.leftT(g, p) = t(j);
                            end
                        end
                    end
                end
            end
            obj.tNow = t(end); obj.whNow = Wh(end, :);
        end

        function T = table(obj)
            % One row per group: time (h) and Wh to convergence per parameter
            T = table((1:13)', 'VariableNames', "Group");
            for p = 1:4
                T.(obj.names(p) + "_h")  = obj.convT(:, p) / 3600;
                T.(obj.names(p) + "_Wh") = obj.convWh(:, p);
                T.(obj.names(p) + "_left_h") = obj.leftT(:, p) / 3600;
            end
        end
    end
end
