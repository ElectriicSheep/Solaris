function S = tabErr(R, P, minCount)
% Table error at visited nodes (count >= minCount) vs truth, per parameter, %.
if nargin < 3, minCount = 50; end
names = ["r0" "r1" "tau"];
for k = 1:3
    est = R.tab.(names(k)); tr = P.truth.(names(k)); c = R.cnt(:,:,:,k);
    e = 100*(est - tr)./tr; v = c >= minCount;
    S.(names(k)).nVisited = nnz(v); S.(names(k)).medAbs = median(abs(e(v))); S.(names(k)).maxAbs = max(abs(e(v)));
    S.(names(k)).init = 100*P.est.initErr.(names(k));
end
S.Q = 100*(R.Qh - P.truth.Q)./P.truth.Q;
end
