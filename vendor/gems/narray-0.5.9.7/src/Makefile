
SHELL = /bin/sh

#### Start of system configuration section. ####

srcdir = .
topdir = /opt/local/include/ruby1.9-1.9.1
hdrdir = /opt/local/include/ruby1.9-1.9.1
arch_hdrdir = /opt/local/include/ruby1.9-1.9.1/$(arch)
VPATH = $(srcdir):$(arch_hdrdir)/ruby:$(hdrdir)/ruby
prefix = $(DESTDIR)/opt/local
exec_prefix = $(prefix)
vendorhdrdir = $(rubyhdrdir)/vendor_ruby
sitehdrdir = $(rubyhdrdir)/site_ruby
rubyhdrdir = $(includedir)/$(RUBY_INSTALL_NAME)-$(ruby_version)
vendordir = $(libdir)/$(RUBY_INSTALL_NAME)/vendor_ruby
sitedir = $(libdir)/$(RUBY_INSTALL_NAME)/site_ruby
mandir = $(DESTDIR)/opt/local/share/man
localedir = $(datarootdir)/locale
libdir = $(exec_prefix)/lib
psdir = $(docdir)
pdfdir = $(docdir)
dvidir = $(docdir)
htmldir = $(docdir)
infodir = $(datarootdir)/info
docdir = $(datarootdir)/doc/$(PACKAGE)
oldincludedir = $(DESTDIR)/usr/include
includedir = $(prefix)/include
localstatedir = $(prefix)/var
sharedstatedir = $(prefix)/com
sysconfdir = $(prefix)/etc
datadir = $(datarootdir)
datarootdir = $(prefix)/share
libexecdir = $(exec_prefix)/libexec
sbindir = $(exec_prefix)/sbin
bindir = $(exec_prefix)/bin
rubylibdir = $(libdir)/$(ruby_install_name)/$(ruby_version)
archdir = $(rubylibdir)/$(arch)
sitelibdir = $(sitedir)/$(ruby_version)
sitearchdir = $(sitelibdir)/$(sitearch)
vendorlibdir = $(vendordir)/$(ruby_version)
vendorarchdir = $(vendorlibdir)/$(sitearch)

CC = /usr/bin/gcc-4.2
CXX = /usr/bin/g++-4.2
LIBRUBY = $(LIBRUBY_SO)
LIBRUBY_A = lib$(RUBY_SO_NAME)-static.a
LIBRUBYARG_SHARED = -l$(RUBY_SO_NAME)
LIBRUBYARG_STATIC = -l$(RUBY_SO_NAME)-static
OUTFLAG = -o 
COUTFLAG = -o 

RUBY_EXTCONF_H = 
cflags   = $(optflags) $(debugflags) $(warnflags)
optflags = -O2
debugflags = -g
warnflags = -Wall -Wno-parentheses
CFLAGS   =  -fno-common -O2 -arch x86_64 $(cflags)  -fno-common -pipe -fno-common 
INCFLAGS = -I. -I$(arch_hdrdir) -I$(hdrdir)/ruby/backward -I$(hdrdir) -I$(srcdir)
DEFS     = 
CPPFLAGS = -DHAVE_SYS_TYPES_H -DHAVE_U_INT8_T -DHAVE_INT16_T -DHAVE_INT32_T -DHAVE_U_INT32_T -I/opt/local/include -D_XOPEN_SOURCE -D_DARWIN_C_SOURCE $(DEFS) $(cppflags)
CXXFLAGS = $(CFLAGS) -O2 -arch x86_64 $(cxxflags)
ldflags  = -L. -L/opt/local/lib -L/usr/local/lib
dldflags = 
archflag = 
DLDFLAGS = $(ldflags) $(dldflags) $(archflag)
LDSHARED = cc -dynamic -bundle -undefined suppress -flat_namespace
LDSHAREDXX = $(LDSHARED)
AR = ar
EXEEXT = 

RUBY_INSTALL_NAME = ruby1.9
RUBY_SO_NAME = ruby1.9
arch = i386-darwin10
sitearch = i386-darwin10
ruby_version = 1.9.1
ruby = /opt/local/bin/ruby1.9
RUBY = $(ruby)
RM = rm -f
RM_RF = $(RUBY) -run -e rm -- -rf
RMDIRS = $(RUBY) -run -e rmdir -- -p
MAKEDIRS = mkdir -p
INSTALL = /usr/bin/install -c
INSTALL_PROG = $(INSTALL) -m 0755
INSTALL_DATA = $(INSTALL) -m 644
COPY = cp

#### End of system configuration section. ####

preload = 

libpath = . $(libdir)
LIBPATH =  -L. -L$(libdir)
DEFFILE = 

CLEANFILES = mkmf.log
DISTCLEANFILES = 
DISTCLEANDIRS = 

extout = 
extout_prefix = 
target_prefix = 
LOCAL_LIBS = 
LIBS = $(LIBRUBYARG_SHARED)  -lpthread -ldl -lobjc  
SRCS = narray.c na_array.c na_func.c na_index.c na_random.c na_op.c na_math.c na_linalg.c
OBJS = narray.o na_array.o na_func.o na_index.o na_random.o na_op.o na_math.o na_linalg.o
TARGET = narray
DLLIB = $(TARGET).bundle
EXTSTATIC = 
STATIC_LIB = 

BINDIR        = $(bindir)
RUBYCOMMONDIR = $(sitedir)$(target_prefix)
RUBYLIBDIR = /Users/choffstein/Documents/Projects/portfolio-analysis/vendor/gems/narray-0.5.9.7/.$(target_prefix)
RUBYARCHDIR = /Users/choffstein/Documents/Projects/portfolio-analysis/vendor/gems/narray-0.5.9.7/.$(target_prefix)
HDRDIR        = $(rubyhdrdir)/ruby$(target_prefix)
ARCHHDRDIR    = $(rubyhdrdir)/$(arch)/ruby$(target_prefix)

TARGET_SO     = $(DLLIB)
CLEANLIBS     = $(TARGET).bundle 
CLEANOBJS     = *.o  *.bak

all:    $(DLLIB)
static: $(STATIC_LIB)

clean-rb-default::
clean-rb::
clean-so::
clean: clean-so clean-rb-default clean-rb
		@-$(RM) $(CLEANLIBS) $(CLEANOBJS) $(CLEANFILES)

distclean-rb-default::
distclean-rb::
distclean-so::
distclean: clean distclean-so distclean-rb-default distclean-rb
		@-$(RM) Makefile $(RUBY_EXTCONF_H) conftest.* mkmf.log
		@-$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES)
		@-$(RMDIRS) $(DISTCLEANDIRS)

realclean: distclean
install: install-so install-rb

install-so: $(RUBYARCHDIR)
install-so: $(RUBYARCHDIR)/$(DLLIB)
$(RUBYARCHDIR)/$(DLLIB): $(DLLIB)
	$(INSTALL_PROG) $(DLLIB) $(RUBYARCHDIR)
install-rb: pre-install-rb install-rb-default
install-rb-default: pre-install-rb-default
pre-install-rb: Makefile
pre-install-rb-default: Makefile
pre-install-rb-default: $(RUBYLIBDIR)
install-rb-default: $(RUBYLIBDIR)/narray_ext.rb
$(RUBYLIBDIR)/narray_ext.rb: $(srcdir)/lib/narray_ext.rb
	$(INSTALL_DATA) $(srcdir)/lib/narray_ext.rb $(@D)
install-rb-default: $(RUBYLIBDIR)/nmatrix.rb
$(RUBYLIBDIR)/nmatrix.rb: $(srcdir)/lib/nmatrix.rb
	$(INSTALL_DATA) $(srcdir)/lib/nmatrix.rb $(@D)
pre-install-rb: $(RUBYARCHDIR)
install-rb: $(RUBYARCHDIR)/narray.h
$(RUBYARCHDIR)/narray.h: $(srcdir)/narray.h
	$(INSTALL_DATA) $(srcdir)/narray.h $(@D)
install-rb: $(RUBYARCHDIR)/narray_config.h
$(RUBYARCHDIR)/narray_config.h: $(srcdir)/narray_config.h
	$(INSTALL_DATA) $(srcdir)/narray_config.h $(@D)
$(RUBYLIBDIR):
	$(MAKEDIRS) $@
$(RUBYARCHDIR):
	$(MAKEDIRS) $@

site-install: site-install-so site-install-rb
site-install-so: install-so
site-install-rb: install-rb

.SUFFIXES: .c .m .cc .cxx .cpp .C .o

.cc.o:
	$(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $<

.cxx.o:
	$(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $<

.cpp.o:
	$(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $<

.C.o:
	$(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $<

.c.o:
	$(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(COUTFLAG)$@ -c $<

$(DLLIB): $(OBJS) Makefile
	@-$(RM) $(@)
	$(LDSHARED) -o $@ $(OBJS) $(LIBPATH) $(DLDFLAGS) $(LOCAL_LIBS) $(LIBS)



###
na_op.c: mknafunc.rb mkop.rb
	$(RUBY) -I$(srcdir) $(srcdir)/mkop.rb

na_op.o: na_op.c narray.h $(hdrdir)/ruby/ruby.h


na_math.c: mknafunc.rb mkmath.rb
	$(RUBY) -I$(srcdir) $(srcdir)/mkmath.rb

na_math.o: na_math.c narray.h $(hdrdir)/ruby/ruby.h


cleanall:  clean
	@$(RM)  na_op.c na_math.c
