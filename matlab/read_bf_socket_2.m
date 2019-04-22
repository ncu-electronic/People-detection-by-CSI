%READ_BF_SOCKET Reads in a file of beamforming feedback logs.
%   This version uses the *C* version of read_bfee, compiled with
%   MATLAB's MEX utility.
%
% (c) 2008-2011 Daniel Halperin <dhalperi@cs.washington.edu>
%
%   Modified by Renjie Zhang, Bingxian Lu.
%   Email: bingxian.lu@gmail.com
function read_bf_socket()
clc;
clear all;
while 1
%% Build a TCP Server and wait for connection
    port = 8090;
    t = tcpip('0.0.0.0', port, 'NetworkRole', 'server');
    t.InputBufferSize = 1024;
    t.Timeout = 15;
    fprintf('Waiting for connection on port %d\n',port);
    fopen(t);
    fprintf('Accept connection from %s\n',t.RemoteHost);

%% Set plot parameters
    clf;
    axis([1,30,-10,30]);
    t1=0;
    m1=zeros(31,1);

%%  Starting in R2014b, the EraseMode property has been removed from all graphics objects. 
%%  https://mathworks.com/help/matlab/graphics_transition/how-do-i-replace-the-erasemode-property.html
    [VER DATESTR] = version();
    if datenum(DATESTR) > datenum('February 11, 2014')
        p = plot(t1,m1,'MarkerSize',10);
    else
        p = plot(t1,m1,'EraseMode','Xor','MarkerSize',5);
    end

    xlabel('Subcarrier index');
    ylabel('SNR (dB)');

%% Initialize variables
    csi_entry = [];
    index = -1;                     % The index of the plots which need shadowing
    broken_perm = 0;                % Flag marking whether we've encountered a broken CSI yet
    triangle = [1 3 6];             % What perm should sum to for 1,2,3 antennas
    num = 0;                        % user_defined number for average count
    err_subsci_num = 0;
    sum_count = 40;
    init_count = 5000;
    csi = zeros(3,3,30);
    csi_empty = zeros(1,30);
    csi_rx1_sum = zeros(1,30);        % user_defined csi sum
    status = 0;
    
%% Process all entries in socket
    % Need 3 bytes -- 2 byte size field and 1 byte code
    while 1
        % Read size and code from the received packets
        s = warning('error', 'instrument:fread:unsuccessfulRead');
        try
            field_len = fread(t, 1, 'uint16');
        catch
            warning(s);
            disp('Timeout, please restart the client and connect again.');
            break;
        end

        code = fread(t,1);    
        % If unhandled code, skip (seek over) the record and continue
        if (code == 187) % get beamforming or phy data
            bytes = fread(t, field_len-1, 'uint8');
            bytes = uint8(bytes);
            if (length(bytes) ~= field_len-1)
                fclose(t);
                return;
            end
        else if field_len <= t.InputBufferSize  % skip all other info
            fread(t, field_len-1, 'uint8');
            continue;
            else
                continue;
            end
        end

        if (code == 187) % (tips: 187 = hex2dec('bb')) Beamforming matrix -- output a record
            csi_entry = read_bfee(bytes);
        
            perm = csi_entry.perm;
            Nrx = csi_entry.Nrx;
            if Nrx > 1 % No permuting needed for only 1 antenna
                if sum(perm) ~= triangle(Nrx) % matrix does not contain default values
                    if broken_perm == 0
                        broken_perm = 1;
                        % fprintf('WARN ONCE: Found CSI (%s) with Nrx=%d and invalid perm=[%s]\n', filename, Nrx, int2str(perm));
                    end
                else
                    csi_entry.csi(:,perm(1:Nrx),:) = csi_entry.csi(:,1:Nrx,:);
                end
            end
        end
    
        index = mod(index+1,3);
        csi = get_scaled_csi(csi_entry);

    %CSI data
	%You can use the CSI data here.
        if (status == 0)
            if num < init_count
                csi_rx1_sum = abs(squeeze(csi(1,1,:)).') + csi_rx1_sum;
                disp(abs(squeeze(csi(1,1,:)).'))
                num = num + 1;
                disp(num);
            else
                csi_static = csi_rx1_sum/init_count;
                csi_rx1_sum = csi_empty;
                status = 1;
                num =0;
            end
	%%This plot will show graphics about recent 5 csi packets
        else 
            set(p(31),'XData', [1:30], 'YData', db(csi_static), 'color', 'b', 'linestyle', '-');
            if num < sum_count
               num = num+1;
               csi_rx1_sum = abs(squeeze(csi(1,1,:)).') + csi_rx1_sum ;
            else    
                csi_new = csi_rx1_sum/sum_count;
                %disp(csi_new)
                for n=1:30
                    compare_var = [csi_static(n),csi_new(n)];
                    err(n) = std(compare_var);
                    if err(n) > 2.5
                        err_subsci_num = err_subsci_num + 1;
                    end
                end
                disp(err);
                disp(err_subsci_num);
                if err_subsci_num > 8
                    set(p(index*3 + 1),'XData', [1:30], 'YData', db(csi_new), 'color', 'r', 'linestyle', '-');
                else 
                    set(p(index*3 + 1),'XData', [1:30], 'YData', db(csi_new), 'color', 'g', 'linestyle', '-');
                end
                csi_rx1_sum = csi_empty;
                err_subsci_num = 0;
                num = 0;
                axis([1,30,-10,40]);
                drawnow;
            end
        end
    csi_entry = [];
    end
%% Close file
    fclose(t);
    delete(t);
end

end