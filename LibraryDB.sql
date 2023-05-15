-- create database library
CREATE DATABASE LibraryDB;

USE LIBRARYDB;
GO

--create table member
CREATE TABLE Members (
MemberID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
FirstName NVARCHAR (50) NOT NULL,
LastName NVARCHAR (50) NOT NULL,
DateOfBirth DATE NOT NULL,
MemberEmail  NVARCHAR (100) NULL CHECK(MemberEmail LIKE '%_@_%._%'),
TelephoneNo NVARCHAR (30) NULL CHECK (TelephoneNo LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]')
);

--create table address
CREATE TABLE Address(
AddressID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
MemberID INT NOT NULL FOREIGN KEY (MemberID) REFERENCES Members (MemberID),
CONSTRAINT UK_address_members_MemberID UNIQUE (MemberID),
Address1 NVARCHAR (50) NOT NULL,
Address2 NVARCHAR (50) NULL,
Postcode NVARCHAR (10) NOT NULL,
City NVARCHAR (50) NOT NULL
);

--create member login table
CREATE TABLE MemberLogin(
MemberLoginID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
MemberID INT NOT NULL FOREIGN KEY (MemberID) REFERENCES Members (MemberID),
CONSTRAINT UK_memberlogin_members_MemberID UNIQUE (MemberID),
Username NVARCHAR (50) NOT NULL,
Password NVARCHAR (100) NOT NULL
);

-- create table for start and end
CREATE TABLE MemberStartAndEndDate(
MemberStartAndEndDateID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
MemberID INT  NOT NULL FOREIGN KEY (MemberID) REFERENCES Members (MemberID),
JoinedDate DATE NOT NULL,
DateLeft DATE NULL
);

--create library catalogue
create table ItemCatalogue(
ItemID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
ItemTitle NVARCHAR (100) NOT NULL,
ItemType NVARCHAR (50) NOT NULL,
Author NVARCHAR (100) NOT NULL,
YearOfPublication INT NOT NULL,
DateAdded DATE NOT NULL,
ItemStatus NVARCHAR(50) NOT NULL,
DateRemoved DATE NULL,
ISBN NVARCHAR(50) NULL,
);

--create table for loans
create table Loans(
LoanID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
MemberID INT NOT NULL FOREIGN KEY (MemberID) REFERENCES Members (MemberID),
ItemID INT NOT NULL FOREIGN KEY (ItemID) REFERENCES ItemCatalogue (ItemID),
DateIssued DATE NOT NULL,
DateDue DATE NULL,
DateReturned DATE NULL,
OverdueFees MONEY DEFAULT 0.00
);

--create table for overdue fines
create table OverdueFine(
OverdueFineID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
LoanID INT NOT NULL FOREIGN KEY (LoanID) REFERENCES Loans(LoanID),
FineOwed MONEY DEFAULT 0.00,
FinePaid MONEY DEFAULT 0.00,
Outstanding MONEY DEFAULT 0.00
);

--create table for payments
create table Payment(
PaymentID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
OverdueFineID INT NOT NULL FOREIGN KEY (OverdueFineID) REFERENCES overdueFine (OverdueFineID),
DatePaid DATE NOT NULL,
AmountPaid MONEY DEFAULT 0.00,
MethodOfPayment NVARCHAR (50) NOT NULL
);

--Create triggers and stored procedure

--trigger to set due date
DROP TRIGGER IF EXISTS SetDueDate;
GO
CREATE TRIGGER SetDueDate ON Loans
AFTER INSERT
AS
BEGIN
    UPDATE Loans
    SET DateDue = DATEADD(day, 7, DateIssued)
END;

--trigger to calculate over due amount
DROP TRIGGER IF EXISTS OverdueAmount;
GO
CREATE TRIGGER OverdueAmount ON Loans
AFTER UPDATE
AS
BEGIN
  DECLARE @DaysOverdue INT;
  
  -- Calculate the number of days overdue
  SELECT @DaysOverdue = DATEDIFF(day, DateDue, DateReturned)
  FROM Loans
 
  -- Update the overdue fine column if the book is overdue
  IF @DaysOverdue > 0
  BEGIN
    UPDATE Loans
    --SET OverdueFees = @DaysOverdue  * 10
	SET OverdueFees = DATEDIFF(day, DateDue, DateReturned) * 10
	WHERE DATEDIFF(day, DateDue, DateReturned) > 0;
  END
END;

--trigger to add fine in overdue table
DROP TRIGGER IF EXISTS UpdateFinePaid;
GO
CREATE TRIGGER UpdateFinePaid
ON payment
AFTER INSERT
AS
BEGIN
	UPDATE OverdueFine
	set FinePaid = i.AmountPaid
	from OverdueFine o
	INNER JOIN inserted i 
	ON o.overduefineid = i.overduefineid
	where o.overduefineid = i.overduefineid
END;

--trigger to calculate outstanding balance
DROP TRIGGER IF EXISTS CalculateOutstanding;
GO
CREATE TRIGGER CalculateOutstanding
ON OverdueFine
AFTER INSERT, UPDATE
AS
BEGIN
    UPDATE OverdueFine
    SET Outstanding = o.FineOwed - o.FinePaid
    FROM OverdueFine o
    INNER JOIN inserted i ON o.loanID = i.loanID
END;

--trigger insert overduefees into overduefine column
DROP TRIGGER IF EXISTS InsertOverdueFees;
GO
CREATE TRIGGER InsertOverdueFees
ON loans
AFTER UPDATE
AS
BEGIN
    IF UPDATE(DateReturned)
    BEGIN
        INSERT INTO overduefine (LoanID)
        SELECT LoanID
        FROM inserted 
    END
	BEGIN
		UPDATE OverdueFine
		SET FineOwed = l.OverdueFees
		FROM overduefine o
		INNER JOIN inserted i 
		ON o.LoanID = i.LoanID
		INNER JOIN Loans l
		ON i.LoanID = l.LoanID
		--where i.DateReturned is not null and o.FineOwed is null
	END
END;

--trigger to set item status to On Loan
DROP TRIGGER IF EXISTS SetItemStatusToLoan;
GO
CREATE TRIGGER SetItemStatusToLoan
ON loans
AFTER INSERT
AS
BEGIN
    UPDATE itemCatalogue
    SET ItemStatus = 'On Loan'
    FROM itemCatalogue ic
    INNER JOIN inserted i
	ON ic.itemid = i.itemid
    WHERE i.datereturned IS NULL
        AND ic.ItemStatus = 'Available'
END;

--trigger to set item status to available
DROP TRIGGER IF EXISTS SetItemStatusToAvailable;
GO
CREATE TRIGGER SetItemStatusToAvailable
ON loans
AFTER UPDATE
AS
BEGIN
    UPDATE itemCatalogue
    SET ItemStatus = 'Available'
    FROM itemCatalogue ic
    INNER JOIN inserted i
	ON ic.itemid = i.itemid
    WHERE i.datereturned IS NOT NULL
        AND ic.ItemStatus = 'On Loan'
END;

-- procedure to update date returned
DROP PROCEDURE IF EXISTS UpdateLoanDateReturned;
GO
CREATE PROCEDURE UpdateLoanDateReturned
    @LoanID INT,
    @DateReturned DATE
AS
BEGIN
    UPDATE Loans
    SET DateReturned = @DateReturned
    WHERE LoanID = @LoanId;
END;

--procedure to insert payment into a database
DROP PROCEDURE IF EXISTS MakePayment;
GO
CREATE PROCEDURE MakePayment
    @OverdueFineID INT,
    @AmountPaid MONEY,
    @MethodOfPayment VARCHAR(50)
AS
BEGIN
    INSERT INTO Payment (OverdueFineID, DatePaid, AmountPaid, MethodOfPayment)
    VALUES (@OverdueFineID, convert (date, GETDATE()), @AmountPaid, @MethodOfPayment);
END;

exec MakePayment @OverdueFineID = 1, @AmountPaid = 20.00, @MethodOfPayment = 'Credit Card'

--procedure to get loan
DROP PROCEDURE IF EXISTS GetLoan;
GO
CREATE  PROCEDURE GetLoan
	@memberId INT,
	@itemId INT,
	@dateIssued Date
AS 
BEGIN
	insert into loans(MemberID, ItemID, DateIssued) 
	values (@memberId, @itemId, @dateIssued)
END;

--procedure to add item into catalogue
DROP PROCEDURE IF EXISTS AddItem;
GO
CREATE PROCEDURE AddItem
	@itemTitle NVARCHAR(100),
	@itemType NVARCHAR(50),
	@author NVARCHAR(100),
	@yearOfPublication INT,
	@dateAdded DATE,
	@itemStatus NVARCHAR(50),
	@dateRemoved DATE = NULL,
	@ISBN NVARCHAR(100) = NULL
AS
BEGIN
    INSERT INTO ItemCatalogue (ItemTitle, ItemType, Author, YearOfPublication, DateAdded, ItemStatus, DateRemoved, ISBN)
    VALUES ( @itemTitle, @itemType, @author, @yearOfPublication, @dateAdded, @itemStatus, @dateRemoved, @ISBN);
End;

--stored procedure to search ItemCatalogue by title
DROP PROCEDURE IF EXISTS SearchItemCatalogueByTitle;
GO
CREATE PROCEDURE SearchItemCatalogueByTitle
    @searchString VARCHAR(100)
AS
BEGIN
    SELECT *
    FROM ItemCatalogue
    WHERE itemtitle LIKE '%' + @searchString + '%'
    ORDER BY yearofpublication DESC
END

--calling the stored procedure to search for ADB
exec SearchItemCatalogueByTitle @searchString = 'ADB'

--stored procedure to get loan items due in 5 days or less
DROP PROCEDURE IF EXISTS GetItemsDueIn5Days;
GO
CREATE PROCEDURE GetItemsDueIn5Days
AS
BEGIN
    SELECT l.*, i.itemtitle, m.firstname, m.lastname, m.memberemail, m.telephoneno
    FROM Loans l
    INNER JOIN ItemCatalogue i ON l.itemid = i.itemid
    INNER JOIN members m ON l.memberid = m.memberid
    WHERE l.DateReturned IS NULL AND l.DateDue <= DATEADD(day, 5, GETDATE())
END

exec GetItemsDueIn5Days
--stored procedure to create a new member
DROP PROCEDURE IF EXISTS AddMember;
GO
CREATE PROCEDURE AddMember
	@firstname VARCHAR(50),
    @lastname VARCHAR(50),
	@dateofbirth DATE,
	@memberEmail VARCHAR(50) = NULL,
    @telephoneNo VARCHAR(20) = NULL,
	@JoinedDate Date,
	@DateLeft Date = NULL,
	@address1 NVARCHAR(100),
	@address2 NVARCHAR(100),
	@city NVARCHAR(100),
	@postcode NVARCHAR(50),
	@username NVARCHAR (50),
	@password NVARCHAR (100)
	
AS
BEGIN
	DECLARE @memberID INT
	DECLARE @hashedpassword VARBINARY
	SET @hashedPassword = HASHBYTES('SHA2_512', @password)
    INSERT INTO members (firstname, lastname, dateofbirth, memberemail, telephoneno)
    VALUES ( @firstname, @lastname, @dateofbirth, @memberemail, @telephoneno);
	set @memberID = SCOPE_IDENTITY();
	INSERT INTO Address (MemberID, Address1, Address2, City, Postcode) 
	VALUES (@memberID, @address1, @address2, @city, @postcode);
	INSERT INTO MemberStartAndEndDate (MemberID, JoinedDate, DateLeft) 
	VALUES (@memberID, @JoinedDate, @DateLeft)
	INSERT INTO MemberLogin (MemberID, Username, Password) 
	VALUES (@memberID, @username, @hashedPassword)
END

--update member details
DROP PROCEDURE IF EXISTS UpdateMember;
GO
CREATE PROCEDURE UpdateMember
	@memberid INT,
	@firstname NVARCHAR(50),
    @lastname NVARCHAR(50),
	@dateofbirth DATE,
	@memberEmail NVARCHAR(50) = NULL,
    @telephoneNo NVARCHAR(20) = NULL,
	@JoinedDate Date,
	@DateLeft Date = NULL,
	@username NVARCHAR (50),
	@password NVARCHAR (100),
	@address1 NVARCHAR(100),
	@address2 NVARCHAR(100),
	@city NVARCHAR(100),
	@postcode NVARCHAR(50)

AS
BEGIN
    UPDATE Members
    SET firstname = @firstname,
				lastname = @lastname,
				dateofbirth = @dateofbirth,
				memberemail = @memberemail,
				telephoneno = @telephoneno
	WHERE memberid = @memberid
	UPDATE Address
	SET address1 = @address1,
			address2 = @address2,
			city = @city,
			postcode = @postcode
	WHERE memberid = @memberid
	Update MemberStartAndEndDate
	SET JoinedDate = @JoinedDate,
			DateLeft = @DateLeft
	WHERE memberid = @memberid
	UPDATE MemberLogin
	SET Username = @username,
			Password = HASHBYTES('SHA2_512', @password)
    WHERE memberid = @memberid
END

--view to display loan history
DROP VIEW IF EXISTS LoanHistory;
GO
CREATE VIEW LoanHistory 
AS
SELECT 
    l.loanid, 
    m.firstname AS member_firstname, 
	m.lastname AS member_lastname, 
    i.itemtitle, 
    i.itemtype, 
    i.author, 
    i.yearofpublication, 
    l.dateissued, 
    l.datedue, 
    l.datereturned, 
    l.overduefees
FROM Loans l
INNER JOIN itemcatalogue i ON l.itemid = i.itemid
INNER JOIN members m ON l.memberid = m.memberid

select * from LoanHistory
--function to identify the total number of loans made in a day
DROP FUNCTION IF EXISTS TotalLoansOnDate;
GO
CREATE FUNCTION TotalLoansOnDate (@date DATE)
RETURNS INT
AS
BEGIN
    DECLARE @total INT
    SELECT @total = COUNT(*)
    FROM Loans
    WHERE CONVERT(DATE, DateIssued) = @date
    RETURN @total
END

--retrieving loans on the 29th of march, 2023
SELECT dbo.TotalLoansOnDate('2023-03-29') as 'Total Loans'

--function to display the total number of loans made in a day and the books borrowed
DROP FUNCTION IF EXISTS ItemsBorrowedOnDate;
GO
CREATE FUNCTION ItemBorrowedOnDate(@date date)
RETURNS @result TABLE (num_items_borrowed int, books_borrowed varchar(max))
AS
BEGIN
    INSERT INTO @result (num_items_borrowed, books_borrowed)
    SELECT COUNT(*) AS num_items_borrowed, STRING_AGG(i.itemTitle, ', ') AS items_borrowed
	    FROM Loans l
	inner join ItemCatalogue i
	on l.itemiD = i.ItemID
    WHERE DateIssued = @date;
    RETURN;
END;

--retrieving count of loans taken on the 29th of march, 2023 with book title
SELECT * FROM dbo.ItemBorrowedOnDate('2023-04-05');

--retrieving loans on the 29th of march, 2023
SELECT dbo.TotalLoansOnDate('2023-03-29') as 'Total Loans'

--retrieving loans on the 29th of march, 2023 with book title
SELECT * FROM dbo.BooksBorrowedOnDate('2023-04-05');

--Testing the database objects created

--add members into member, address, memberlogin and memberStartAndEndDate tables
exec AddMember @firstname = 'Kevwe', @lastname = 'Gift', @dateofbirth = '1987-02-11', 
@memberemail = 'kayka1y@yahoo.com', @telephoneno = '07021894101', @JoinedDate = '2020-11-10',
@address1 = 'street no 1205 ', @address2 = 'conast place', @city = 'salford', @postcode = 'm35 6fg', 
@username = 'kaykay', @password = 'kay12345'

exec AddMember @firstname = 'Flo', @lastname = 'Ego', @dateofbirth = '1991-09-11', 
@memberemail = 'egoflo@yahoo.com', @telephoneno = '07033894101', @JoinedDate = '2020-01-10',
@address1 = 'apartment 1205 ', @address2 = 'new place', @city = 'salford', @postcode = 'm7 6fg', 
@username = 'egoflo', @password = 'flo12345'

exec AddMember @firstname = 'Kos', @lastname = 'Dor', @dateofbirth = '1997-02-11', 
@memberemail = 'kosdor@yahoo.com', @telephoneno = '07021894441', @JoinedDate = '2020-10-10',
@address1 = 'block 62', @address2 = 'quay road', @city = 'salford', @postcode = 'm6 6fg', 
@username = 'kosdor', @password = 'kos12345'

exec AddMember @firstname = 'Amin', @lastname = 'Moh', @dateofbirth = '1990-11-11', 
@memberemail = 'aminmoh@yahoo.com', @telephoneno = '07028894101', @JoinedDate = '2021-10-10',
@address1 = 'apartment no 12', @address2 = 'coplace gardens', @city = 'salford', @postcode = 'm3 6fg', 
@username = 'aminmoh', @password = 'amin12345'

exec AddMember @firstname = 'Abdul', @lastname = 'Ramadan', @dateofbirth = '1990-02-11', 
@memberemail = 'abdulram@yahoo.com', @telephoneno = '07021899901', @JoinedDate = '2020-06-10',
@address1 = 'road 7, flat 5 ', @address2 = 'conast way', @city = 'salford', @postcode = 'm5 6fg', 
@username = 'abdulram', @password = 'ram12345'

exec AddMember @firstname = 'Jon', @lastname = 'Doe', @dateofbirth = '1989-03-01', 
@memberemail = 'jondoe@yahoo.com', @telephoneno = '07066694101', @JoinedDate = '2020-01-15',
@address1 = 'house 205 ', @address2 = 'downing street', @city = 'salford', @postcode = 'm50 6fg', 
@username = 'jondoe', @password = 'jon12345'
select * from Members
--update member details in members, address, memberLogin and memberStartAndEndDate tables
exec UpdateMember @memberid = 6, @firstname = 'John', @lastname = 'Don', @dateofbirth = '1989-11-01', 
@memberemail = 'jodon@yahoo.com', @telephoneno = '07076683101', @JoinedDate = '2020-01-15',
@address1 = 'house 25 ', @address2 = 'downing street', @city = 'salford', @postcode = 'm50 6fg', 
@username = 'jodon', @password = 'don12345'

--adding items into the itemCatalogue table using stored procedures
exec AddItem @itemTitle = 'intro to SQL', @itemType = 'Book', @author = 'DR. K', @yearOfPublication = '2020', @dateAdded = '2020-04-01', @itemStatus = 'Available';
exec AddItem @itemTitle = 'intro to ASDV', @itemType = 'CD', @author = 'DR. N', @yearOfPublication = '2020', @dateAdded = '2020-04-10', @itemStatus = 'Available';
exec AddItem @itemTitle = 'intro to MLDM', @itemType = 'DVD', @author = 'Prof. A', @yearOfPublication = '2021', @dateAdded = '2021-04-05', @itemStatus = 'Available';
exec AddItem @itemTitle = 'intro to Big Data', @itemType = 'Book', @author = 'DR. A', @yearOfPublication = '2021', @dateAdded = '2020-06-21', @itemStatus = 'Available';
exec AddItem @itemTitle = 'intro to ADB', @itemType = 'Book', @author = 'DR. B', @yearOfPublication = '2021', @dateAdded = '2020-07-11', @itemStatus = 'Available';

--inserting into loans using a stored procedure
exec GetLoan @memberId = 3, @itemId = 2, @dateIssued = '2023-04-05'
exec GetLoan @memberId = 2, @itemId = 4, @dateIssued = '2023-03-29'

--updating loan return date
exec UpdateLoanDateReturned @loanID = 2, @DateReturned = '2023-04-08';

--insert into payment table
exec MakePayment @OverdueFineID = 1, @AmountPaid = 20.00, @MethodOfPayment = 'Credit Card'

----calling the stored procedure to search for ADB
exec SearchItemCatalogueByTitle @searchString = 'ADB'

--caling stored procedure to get items due in 5 days or less
exec GetItemsDueIn5Days

--create log in details
CREATE LOGIN JON
WITH PASSWORD = 'jon12345';

--create user
CREATE USER JON FOR LOGIN JON;
GO

--assigning privileges
GRANT SELECT, UPDATE, INSERT ON DATABASE :: LibraryDB TO JON;
