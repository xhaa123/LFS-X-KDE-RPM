Summary:	An XML parser library
Name:		expat
Version:	2.1.0
Release:	1
License:	Custom
URL:		http://expat.sourceforge.net/
Group:		BLFS/GeneralLibraries
Vendor:		Bildanet
Distribution:	Octothorpe
Source0:	http://downloads.sourceforge.net/%{name}-%{version}.tar.gz
%description
The Expat package contains a stream oriented C library for parsing XML.
%prep
%setup -q
%build
./configure \
	CFLAGS="%{optflags}"   \
	CXXFLAGS="%{optflags}" \
	--prefix=%{_prefix}    \
	--bindir=%{_bindir}    \
	--libdir=%{_libdir}    \
	--disable-static
make %{?_smp_mflags}
%install
[ %{buildroot} != "/"] && rm -rf %{buildroot}/*
make DESTDIR=%{buildroot} install
find %{buildroot}/%{_libdir} -name '*.la' -delete
%{_fixperms} %{buildroot}/*
%check
make -k check |& tee %{_specdir}/%{name}-check-log || %{nocheck}
%post	-p /sbin/ldconfig
%postun	-p /sbin/ldconfig
%clean
rm -rf %{buildroot}/*
%files
%defattr(-,root,root)
%{_bindir}/*
%{_libdir}/*.so*
%{_libdir}/pkgconfig/*
%{_includedir}/*
%{_mandir}/man1/*
%changelog
*	Wed May 29 2013 baho-utot <baho-utot@columbus.rr.com> 2.1.0-1
-	Initial build.	First version