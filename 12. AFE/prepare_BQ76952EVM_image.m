function prepare_BQ76952EVM_image
%PREPARE_BQ76952EVM_IMAGE Crop the source board and neutralize only exterior black.
afe=fileparts(mfilename('fullpath'));
src=fullfile(afe,'assets','bq76952evm_top.png');
dst=fullfile(afe,'assets','bq76952evm_top_cropped.png');
I=imread(src); [h,w,~]=size(I);
% The supplied source is RGB without alpha. Only near-black pixels reachable
% from the image perimeter are treated as background; enclosed black PCB
% components, connector details and silkscreen remain untouched.
bg=all(I<=2,3); seen=false(h,w);
edge=[find(bg(1,:)),find(bg(h,:))+h*(h-1), ...
    find(bg(:,1))',find(bg(:,w))'+h*(w-1)];
edge=unique(edge); q=zeros(nnz(bg),1,'uint32'); n=uint32(numel(edge));
q(1:n)=uint32(edge); seen(edge)=true; head=uint32(1);
while head<=n
    ix=double(q(head)); row=mod(ix-1,h)+1; col=floor((ix-1)/h)+1;
    if row>1 && bg(ix-1) && ~seen(ix-1), n=n+1; q(n)=uint32(ix-1); seen(ix-1)=true; end
    if row<h && bg(ix+1) && ~seen(ix+1), n=n+1; q(n)=uint32(ix+1); seen(ix+1)=true; end
    if col>1 && bg(ix-h) && ~seen(ix-h), n=n+1; q(n)=uint32(ix-h); seen(ix-h)=true; end
    if col<w && bg(ix+h) && ~seen(ix+h), n=n+1; q(n)=uint32(ix+h); seen(ix+h)=true; end
    head=head+1;
end
foreground=~seen; [rr,cc]=find(foreground); pad=5;
r1=max(1,min(rr)-pad); r2=min(h,max(rr)+pad);
c1=max(1,min(cc)-pad); c2=min(w,max(cc)+pad);
J=I(r1:r2,c1:c2,:); exterior=seen(r1:r2,c1:c2);
for k=1:3, plane=J(:,:,k); plane(exterior)=248; J(:,:,k)=plane; end
imwrite(J,dst);
fprintf('Wrote %s (%d x %d pixels; aspect %.6f).\n', ...
    dst,size(J,2),size(J,1),size(J,2)/size(J,1));
end
