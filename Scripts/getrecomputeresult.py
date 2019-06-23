import glob
import errno
#path = '/home/cc/nvc/tests/recompute_result*'
#files = glob.glob(path)
name = "/home/cc/nvc/tests/recompute_result.out.jie"
resultfile = open("/home/cc/nvc/tests/recomputewholeresult.txt","w+")
with open('/home/cc/nvc/tests/wholeresult.txt') as pidlist:
    for pid in pidlist:
        try:
            with open(name+pid.rstrip()) as f:
                line = f.readline()
                resultfile.write(line)
                #resultfile.write("\n")
                f.close()
        except IOError as exc:
            print("error\n")
            if exc.errno != errno.EISDIR:
                raise

resultfile.close()
