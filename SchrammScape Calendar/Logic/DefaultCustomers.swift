//
//  DefaultCustomers.swift
//  SchrammScape Calendar
//
//  The default MOW_REF customer list, seeded on first launch.
//  Synced from the Supabase `customers` table on 2026-07-01.
//

import Foundation

enum DefaultCustomers {
    static let all: [ParsedCustomer] = CSVSupport.parseCustomers(csv)

    private static let csv = """
    Customer,Address,Title,duration,DOW,Mower,Details,Phone,Height,Frequency
    *Hellen Allison,"2086 Canturbury Ct, Troy OH 45373",PREVIOUS CUSTOMER,TBD,,,,,
    Mayanne Vrabel,"3343 W Farrington Rd, Piqua, OH 45356",PREVIOUS CUSTOMER,TBD,,,,,
    Lynn Darden,"764 N Dorset, Troy OH 45373",Mowing Lynn Darden,45,MON,42,,,3.5
    Joel Morrow,"826 Branford Road, Troy OH 45373",Mowing Joel Morrow,50,MON,42,"Text ahead, cut grass short to help with dog poo cleanup, mower is very tight fit into backyard.",937-416-4632,3
    Roxanne Stockslager,"681 Branford Rd, Troy OH 45373",Mowing Roxanne Stockslager,50,MON,42,,937-371-5350,3.5
    Ashley Dean,"849 Gearhardt Ln, Troy OH 45373",Mowing Ashley Dean,50,MON,42,"push mow small fenced in backyard, mow at least 1 strip around fence",,3.5
    Destiny Tomlin,"2439 Medowpoint Dr, Troy OH 45373",Mowing Destiny Tomlin,40,MON,42,Trampoline to weedeat under,,3.5
    Amy Dillow,"404 W Canal St, Troy OH 45373",Mowing Amy Dillow,45,MON,42+PUSH,Corner Lot - Avoid the neighbors Lexus,,
    Jeremiah Pierce,"525 S Counts St, Troy OH 45373",Mowing Jeremiah Pierce,60,TUE,42,Corner Lot - Mower is very tight fit into backyard,937-524-4946,3.5
    Katherine Harding,"403 S Walnut, Troy, OH 45373",Mowing Katherine Harding,50,TUE,42+PUSH,"Corner Lot, LOTS of edging on sidewalks, steep yard on front needs push mower",,3.5
    Ethan Neff,"814 S Clay St, Troy OH 45373",Mowing Ethan Neff,45,TUE,PUSH,must lift mower up onto property,,3.5
    Jennifer Holloway,"131 Southview Dr. , Troy OH 45373",Mowing Jennifer Holloway,45,TUE,,,,
    Sargram Merchant,"1204 Maple St, Troy OH 45373",Mowing Sargram Merchant,40,TUE,42,"Text to unlock gate, lots of ditch and culvert work, very little grass, lots of trees to work around",937-716-4195,3.5
    Anne Brill,"2572 Renwick Way, Troy OH 45373",Mowing Anne Brill,50,WED,42,"Lawn goes to pond, be very careful",,3.5
    Lisa Chaney,"3372 Diamondback Dr, Dayton, OH 45414",Mowing Lisa Chaney,45,WED,,,,
    Daniel Garcia,"4603 Dartford Rd, Englewood, OH  45322",Mowing Daniel Garcia,45,WED,,,,
    Lisa Ott,"522 Summit Ave, Troy OH 45373",Mowing Lisa Ott,35,THU,,,,
    Mike Monroe,"611 Summit Ave, Troy OH 45373",Mowing Mike Monroe,45,THU,,,480-316-9644,
    Ducky's Ice Cream,"100 W Market St, Troy OH 45373",Mowing Ducky's Ice Cream,30,THU,,,,
    Sarah Haight,"1604 Grey Hawk Ct, Troy OH 45373",Mowing Sarah Haight,40,THU,,,,
    Larry Picklesimer,"604 Medow Ln, Troy OH 45373",Mowing Larry Picklesimer,45,FRI,,,937-216-2033,
    Kayle DuRall,"1291 Skylark Dr, Troy OH 45373",Mowing Kayle DuRall,35,FRI,,,,
    Sarah Kelley,"1305 Skylark Dr, Troy OH 45373",Mowing Sarah Kelley,40,FRI,,,,
    Laura Hale,"1427 Sussex Rd, Troy OH 45373",Mowing Laura Hale,40,FRI,,,513-706-4564,
    Roma Cress,"1291 York Ln, Troy OH 45373",Mowing Roma Cress,45,FRI,PUSH,Must collect push mower clippings and dump in backyard woods,,3.5
    Spencer Thomas Duplex,"670 Armond Dr, Troy OH 45373",Mowing Spencer Thomas Duplex,50,FRI,42,"Needs short grass for weekend enjoyment, cut late in the week",,3.5
    Richard Pierce Rental,"502 Fernwood, Troy, OH 45373",Mowing Richard Pierce Rental,40,,,Bi-Weekly,,,2
    """
}
