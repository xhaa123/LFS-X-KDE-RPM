Summary:	
Name:		
Version:	
Release:	1
License:	GPL
URL:		
Group:		System
Vendor:		Future
Distribution:	Future
Source0:	%{name}-%{version}.tar.bz2

%description

%prep
%setup -q 

%build

%install
[ %{buildroot} != "/"] && rm -rf %{buildroot}/*
make DESTDIR=%{buildroot} install

%{_fixperms} %{buildroot}/*

%check

%post

%clean
rm -rf %{buildroot}/*

%files
%defattr(-,root,root)

%changelog
*	Thu Apr 29 2021 xhaa123 <xhaa123@163.com>
-	Initial build.	First version
